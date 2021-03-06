##
#  <copyright>
#  Copyright 2002 InfoEther, LLC
#  under sponsorship of the Defense Advanced Research Projects Agency (DARPA).
#
#  This program is free software; you can redistribute it and/or modify
#  it under the terms of the Cougaar Open Source License as published by
#  DARPA on the Cougaar Open Source Website (www.cougaar.org).
#
#  THE COUGAAR SOFTWARE AND ANY DERIVATIVE SUPPLIED BY LICENSOR IS
#  PROVIDED 'AS IS' WITHOUT WARRANTIES OF ANY KIND, WHETHER EXPRESS OR
#  IMPLIED, INCLUDING (BUT NOT LIMITED TO) ALL IMPLIED WARRANTIES OF
#  MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE, AND WITHOUT
#  ANY WARRANTIES AS TO NON-INFRINGEMENT.  IN NO EVENT SHALL COPYRIGHT
#  HOLDER BE LIABLE FOR ANY DIRECT, SPECIAL, INDIRECT OR CONSEQUENTIAL
#  DAMAGES WHATSOEVER RESULTING FROM LOSS OF USE OF DATA OR PROFITS,
#  TORTIOUS CONDUCT, ARISING OUT OF OR IN CONNECTION WITH THE USE OR
#  PERFORMANCE OF THE COUGAAR SOFTWARE.
# </copyright>
#

require 'rexml/document'

module Cougaar
  module Actions
    class GetAgentCompletion < Cougaar::Action
      PRIOR_STATES = ["SocietyRunning"]
      DOCUMENTATION = Cougaar.document {
        @description = "Gets an individual agent's completion statistics."
        @parameters = [
          {:agent => "required, The name of the agent."}
        ]
        @block_yields = [
          {:stats => "The completion statistics object (UltraLog::Completion)."}
        ]
        @example = "
          do_action 'GetAgentCompletion', 'NCA' do |stats|
            puts stats
          end
        "
      }
      def initialize(run, agent_name, &block)
        super(run)
        @agent_name = agent_name
        @action = block
      end
      def perform
        @action.call(::UltraLog::Completion.status(@run.society.agents[@agent_name]))
      end
    end
  
    class SaveSocietyCompletion < Cougaar::Action
      PRIOR_STATES = ["SocietyRunning"]
      DOCUMENTATION = Cougaar.document {
        @description = "Gets all agent's completion statistics and writes them to a file."
        @parameters = [
          {:file => "required, The file name to write to."}
        ]
        @example = "do_action 'SaveSocietyCompletion', 'completion.xml'"
      }
      def initialize(run, file)
        super(run)
        @file = file
      end
      def perform
        agent_list = []
        total_tasks = 0 
        total_root_PS = 0
        total_root_supply = 0
        total_root_trans = 0
        @run.society.each_agent {|agent| agent_list << agent.name}
        agent_list.sort!
        xml = "<CompletionSnapshot>\n"
        agent_list.each do |agent|
          begin
            stats = ::UltraLog::Completion.status(@run.society.agents[agent])
            if stats
              xml += stats.to_s
              total_tasks = total_tasks + stats.total.to_i
              total_root_PS = total_root_PS + stats.rootPS.to_i
              total_root_supply = total_root_supply + stats.rootSupply.to_i
              total_root_trans = total_root_trans + stats.rootTransport.to_i
            else
              xml += "<SimpleCompletion agent='#{agent}' status='Error: Could not access agent.'\>\n"
              @run.error_message "Error accessing completion data for Agent #{agent}."
            end
          rescue Exception => failure
            xml += "<SimpleCompletion agent='#{agent}' status='Error: Parse exception.'\>\n"
            @run.error_message "Error parsing completion data for Agent #{agent}: #{failure}."
          end
        end
        xml += "<TotalSocietyTasks>" + total_tasks.to_s + "</TotalSocietyTasks>\n"
        xml += "<TotalRootPSTasks>" + total_root_PS.to_s + "</TotalRootPSTasks>\n"
        xml += "<TotalRootSupplyTasks>" + total_root_supply.to_s + "</TotalRootSupplyTasks>\n"
        xml += "<TotalRootTransportTasks>" + total_root_trans.to_s + "</TotalRootTransportTasks>\n"
        xml += "</CompletionSnapshot>"
        save(xml)
      end
      def save(result)
        Dir.mkdir("COMPS") unless File.exist?("COMPS")
        File.open(File.join("COMPS", @file), "wb") do |file|
          file.puts result
        end
        @run.archive_and_remove_file(File.join("COMPS", @file), "Society completion data.")
      end
    end

    class InstallCompletionMonitor < Cougaar::Action
      PRIOR_STATES = ["SocietySynchronized"]
      RESULTANT_STATE = "CompletionMonitorInstalled"
      DOCUMENTATION = Cougaar.document {
        @description = ""
        @parameters = []
        @example = " do_action 'InstallCompletionMonitor' "
      }
      def initialize(run, debug=false)
        super(run)
        @debug = debug
      end
      def perform
        @monitor = UltraLog::SocietyCompletionMonitor.new(run.society, @debug, run)
        run["completion_monitor"] = @monitor
        run.comms.on_cougaar_event do |event|
          handleEvent(event) if (event.component == "QuiescenceReportServiceProvider")
        end
        run.comms.add_command("print_quiescent_state", "Prints the entire structure used to maintain quisecence state") do |message, params| 
          message.reply.set_body('Printing status to run.log').send
          @monitor.print_current_comp
        end
        run.comms.add_command("check_quiescent_state", "Forces a check of quiescent state, and prints the results with debug on") do |message, params| 
          message.reply.set_body('Printing results to run.log').send
          current_debug = @monitor.debug
          @monitor.debug = true
          @monitor.update_society_status
          @monitor.debug = current_debug
        end
      end

      def handleEvent(event)
        begin
          data = event.data.split(":")
          new_state = data[1].strip
          xml = REXML::Document.new(new_state)
        rescue Exception => failure
          run.error_message "Exception: #{failure}"
          run.error_message "Invalid xml Quiesence message in event: #{event}"
          run.info_message "WARNING: Received bad event - more info in log file"
          return
        end
        @monitor.handleXML(xml.root)
      end
    end

  end  # Module Actions

  module States

    class CompletionMonitorInstalled < Cougaar::NOOPState
      DOCUMENTATION = Cougaar.document {
        @description = "Society quiescence is being actively monitored."
      }
    end
    
    class SocietyQuiesced < Cougaar::State
      DEFAULT_TIMEOUT = 60.minutes
      PRIOR_STATES = ["CompletionMonitorInstalled"]
      DOCUMENTATION = Cougaar.document {
        @description = "Waits for ACME to report that the society has quiesced ."
        @parameters = [
          {:timeout => "default=nil, Amount of time to wait in seconds."},
          {:block => "The timeout handler (unhandled: StopSociety, StopCommunications)"}
        ]
        @example = "
          wait_for 'SocietyQuiesced', 2.hours do
            puts 'Did not get Society Quiesced!!!'
            do_action 'StopSociety'
            do_action 'StopCommunications'
          end
        "
      }
      
      def initialize(run, timeout=nil, &block)
        super(run, timeout, &block)
      end
      
      def process
        comp = @run["completion_monitor"] 
        if (comp.getSocietyStatus() == "COMPLETE")
          # Put this in the log file only...
          Cougaar.logger.info  "[#{Time.now}]      INFO: Society is already quiescent. About to block waiting for society to go non-quiescent, then quiescent again...."
        end
        comp.wait_for_change_to_state("COMPLETE")
      end
      
      def unhandled_timeout
        @run.do_action "StopSociety"
        @run.do_action "StopCommunications"
      end
    end

  end  # Module States
end

module UltraLog
  ##
  # The Completion class wraps access the data generated by the completion servlet
  #
  class Completion
  
    ##
    # Helper method that extracts the host and agent name to get completion for
    #
    # agent:: [Cougaar::Agent] The agent to get completion for
    # return:: [UltraLog::Completion::Statistics] The results of the query
    #
    def self.status(agent)
      data = Cougaar::Communications::HTTP.get("#{agent.uri}/completion?format=xml", 60)
      if data
        return Statistics.new(agent.name, data[0])
      else
        return nil
      end
    end
    
    ##
    # Gets completion statistics for a host/agent
    #
    # host:: [String] Host name
    # agent:: [String] Agent name
    # return:: [UltraLog::Completion::Statistics] The results of the query
    #
    def self.query(host, agent, port)
      data = Cougaar::Communications::HTTP.get("http://#{host}:#{port}/$#{agent}/completion?format=xml", 60)
      if data
        return Statistics.new(agent, data[0])
      else
        return nil
      end
    end
    
    ##
    # The statistics class holds the results of a completion query
    #
    class Statistics
      attr_reader :agent, :time, :total, :unplanned, :unestimated, :unconfident, :failed, :rootPS, :rootSupply, :rootTransport
      
      ##
      # Parses the supplied XML data into the statistics attributed
      #
      # data:: [String] A completion XML query
      #
      def initialize(agent, data)
        begin
          xml = REXML::Document.new(data)
        rescue REXML::ParseException
          raise "Could not construct Statistics object from supplied data."
        end
        root = xml.root
        @agent = agent
        @time = root.elements["TimeMillis"].text.to_i
        @ratio = root.elements["Ratio"].text.to_f
        @total = root.elements["NumTasks"].text.to_i
        @unplanned = root.elements["NumUnplannedTasks"].text.to_i
        @unestimated = root.elements["NumUnestimatedTasks"].text.to_i
        @unconfident = root.elements["NumUnconfidentTasks"].text.to_i
        @failed = root.elements["NumFailedTasks"].text.to_i
        @rootPS = root.elements["NumRootProjectSupplyTasks"].text.to_i
        @rootSupply = root.elements["NumRootSupplyTasks"].text.to_i
        @rootTransport = root.elements["NumRootTransportTasks"].text.to_i
      end

      
      ##
      # Checks if agent is complete
      #
      # return:: [Boolean] true if unplanned and unestimated are zero, false otherwise
      #
      def complete?
        return (@unplanned==0 and @unestimated==0)
      end
      
      ##
      # Checks if agent has failed tasks
      #
      # return:: [Boolean] true if failed > 0, false otherwise
      #
      def failed?
        return (@failed > 0)
      end
      
      def to_s
        s =  "<SimpleCompletion agent='#{@agent}'>\n"
        s << "  <TimeMillis>#{@time}</TimeMillis>\n"
        s << "  <NumTasks>#{@total}</NumTasks>\n"
        if @total==0
          pct = 0
        else
          pct = (@total - @unplanned - @unestimated - @unconfident - @failed) * 100 / @total
        end
        s << "  <Ratio>#{@ratio}</Ratio>\n"
        s << "  <PercentComplete>#{pct}</PercentComplete>\n"
        s << "  <NumUnplannedTasks>#{@unplanned}</NumUnplannedTasks>\n"
        s << "  <NumUnestimatedTasks>#{@unestimated}</NumUnestimatedTasks>\n"
        s << "  <NumUnconfidentTasks>#{@unconfident}</NumUnconfidentTasks>\n"
        s << "  <NumFailedTasks>#{@failed}</NumFailedTasks>\n"
        s << "  <NumRootProjectSupplyTasks>#{@rootPS}</NumRootProjectSupplyTasks>\n"
        s << "  <NumRootSupplyTasks>#{@rootSupply}</NumRootSupplyTasks>\n"
        s << "  <NumRootTransportTasks>#{@rootTransport}</NumRootTransportTasks>\n"
        s << "</SimpleCompletion>\n"
      end
      
    end

  end 

  class SocietyCompletionMonitor
    attr_accessor :debug

    def initialize(society, debug, run=nil)
      @society = society;
      @debug = debug
      @run = run
      @society_status = "INCOMPLETE"
      @comp_status = {}
    end

    def import_from_dump(dump)
      data = []
      if dump.is_a?(String)
        data = dump.split('\n')
      elsif dump.is_a?(Array)
        data = dump
      end
      info = nil
      data.each do |line|
        if (line =~ /Agent: ([A-Za-z0-9].*)$/)
          agent = $1
          @comp_status[agent] = {"recievers" => {}, "senders" => {}} if @comp_status[agent].nil?
        elsif (line =~ /Recievers:/)
          info = @comp_status["recievers"]
        elsif (line =~ /Senders:/)
          info = @comp_status["senders"]  
        elsif (line =~ /::    ([A-Za-z0-9].*) => ([0-9]+)/)
          agent = $1
          id = $2.to_i
          info[agent] = id
        end
      end
    end

    def handleXML(root)
      node_name = root.attributes["name"]
      if root.attributes["quiescent"] == "true"
        root.each_element do |elem|
          agent_name = elem.attributes["name"]
          if agent_name != node_name
            if @society.agents[agent_name] && @society.agents[agent_name].node.name != node_name
              # Got quiescence data for agent from bad (old?) Node
              # Bug 13539
              print "Got quiescence report for #{agent_name} from Node #{node_name} when it should be on #{@society.agents[agent_name].node.name} - ignoring this report"
            else
              @comp_status[agent_name] = get_agent_data(elem)
            end
          end
        end
      else
        node = @society.nodes[node_name]
        node.each_agent do |agent|
          @comp_status[agent.name] = nil
        end
      end
      update_society_status()
    end

    def get_agent_data (data)
      agents = {}
      agents["receivers"] = get_messages(data.elements["receivers"])
      agents["senders"] = get_messages(data.elements["senders"])
      return agents
    end
      
    def get_messages (data)
      msgs = {}
      data.each_element do |elem|
        agent_name = elem.attributes["agent"]
        # throw out any message ids that are to/from node agents
        if @society.nodes[agent_name].nil?
          msgs[agent_name] = elem.attributes["msgnum"]
        end
      end
      return msgs
    end

    def wait_for_change_to_state(wait_for_state, timeout = nil)
      last_state = @society_status
      start = Time.now
      while true
        return false if timeout && (Time.now - start) > timeout
        sleep 5
        # we won't report quiescence if all the agents aren't currently running
        next if !@society.all_agents_running?
        if @society_status != last_state
          # We get some momentary state changes, make sure it stays changed
          sleep 10
          if @society_status != last_state
            last_state = @society_status
            if last_state == wait_for_state
              return true
            end
          end
        end
      end
    end
      
    def print(str)
      if @run.nil?
        puts str
      else
        Cougaar.logger.info str
      end
    end
    
    # Very verbose.  Only call if you really want to see this stuff
    def print_current_comp()
      print "*********************************************************"
      print "PRINTING COMP INFO"
      print "*********************************************************"
      @comp_status.each_key do |agent|
        print "Agent: #{agent}"
        info = @comp_status[agent]
        next if !info
        print "  Receivers:"
        print_messages(info["receivers"])
        print "  Senders:"
        print_messages(info["senders"])
      end
    end

    def print_messages(msgs)
      msgs.each do |agent, msg|
        print "    #{agent} => #{msg}"
      end
    end

    def update_society_status()
      soc_status = "COMPLETE"
      if @society.num_agents > @comp_status.size
        soc_status = "INCOMPLETE"
        print "Quiescence incomplete because not all agents have reported" if @debug
        print "  There are #{@society.num_agents} in the society, but only #{@comp_status.size} have reported" if @debug
      else
        if soc_status != "INCOMPLETE"
          @society.each_agent do |agent|
            agentHash = @comp_status[agent.name]
            if agentHash.nil?
              soc_status = "INCOMPLETE"
              print "Quiescence incomplete because #{agent.name} is not quiescent" if @debug
              break
            end
            agentHash["receivers"].each do |destAgent, msg|
              if !(@comp_status[destAgent])
                soc_status = "INCOMPLETE"
                print "Quiescence incomplete because #{destAgent} is not quiescent" if @debug
                break
              elsif (destMsg = @comp_status[destAgent]["senders"][agent.name]) && destMsg != msg
                soc_status = "INCOMPLETE"
                if @debug
                  print "Quiescence incomplete because:" 
                  print "   src message for #{agent.name} (#{destMsg}) != " 
                  print "       dest message for #{destAgent} (#{msg})" 
                end
                break
              end
            end
            break if soc_status == "INCOMPLETE"

            agentHash["senders"].each do |srcAgent, msg|
              if !(@comp_status[srcAgent])
                soc_status = "INCOMPLETE"
                print "Quiescence incomplete because #{srcAgent} is not quiescent" if @debug
                break
              elsif (srcMsg = @comp_status[srcAgent]["receivers"][agent.name]) && srcMsg != msg
                soc_status = "INCOMPLETE"
                if @debug
                  print "Quiescence incomplete because:" 
                  print "   dest message for #{agent.name} (#{srcMsg}) != " 
                  print "       src message for #{srcAgent} (#{msg})" 
                end
                break
              end
            end
            break if soc_status == "INCOMPLETE"
          end
        end
      end
      unless @society_status == soc_status
        @society_status = soc_status
        if @run.nil?
          puts "**** SOCIETY STATUS IS NOW: #{soc_status} ****"
        else
          @run.info_message "**** SOCIETY STATUS IS NOW: #{soc_status} ****"
        end
      end
    end
  
    def getSocietyStatus()
      return @society_status
    end
 
    def printIncomplete()
      line = "### Incomplete: " 
      @comp_status.each do |agent, status|
        if status == "INCOMPLETE"
          line << "#{agent},"
        end
      end
      return line
    end

  end
end

