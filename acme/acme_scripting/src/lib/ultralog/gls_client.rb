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

require 'uri'

module UltraLog
  class GLSClient
    attr_reader :oplan_name, :oplan_id, :c0_date, :next_stage
    
    def initialize(run)
      @run = run
      @gls_connected = false
      @can_send_oplan = false
      @oplan_name = nil
      @oplan_id = nil
      @c0_date=nil
      @next_stage = nil
      @next_stage_count = 0
      @stages = []
      connect
    end
    
    def connect(uri = nil)
      uri = @run.society.agents['NCA'].uri unless uri
      uri = URI.parse(uri)
      @gls_connection = Net::HTTP.new(uri.host, uri.port)
      @gls_connection.read_timeout = 60*60
      @gls_thread = Thread.new do
        begin
          req = Net::HTTP::Get.new("/$NCA/glsreply?command=connect")
          Cougaar::Communications::HTTP.authenticate_request(req)
          @gls_connection.request(req) do |resp|
            return connect(resp['location']) if resp.code=='302'
            resp.read_body do |data|
              data.each_line do |line|
puts "DATA: #{line.strip}"
                case line.strip
                when /^<oplan name=.* id=[0-9A-F]*>/
                  match = /^<oplan name=(.*) id=([0-9A-F]*)>/.match(data)
                  @oplan_name = match[1]
                  @oplan_id = match[2]
                  @gls_connected = true
                when /^<oplan name=.* id=[0-9A-F]* c0_date=[0-9\/]*>/
                  match = /^<oplan name=(.*) id=([0-9A-F]*) c0_date=([0-9\/]*)>/.match(data)
                  @oplan_name = match[1]
                  @oplan_id = match[2]
                  @c0_date = match[3]
                  @gls_connected = true
                when /^<oplan name=.* id=[0-9A-F]* c0_date=[0-9\/]* nextStage=.*>/
                  match = /^<oplan name=(.*) id=([0-9A-F]*) c0_date=([0-9\/]*) nextStage=(.*)>/.match(data)
                  @oplan_name = match[1]
                  @oplan_id = match[2]
                  @c0_date = match[3]
                  @next_stage = match[4]
                  @stages << @next_stage
                when /^<GLS .*>/
                  @can_send_oplan = true
                end
              end
            end
          end
        rescue
          Cougaar.logger.error $!
          Cougaar.logger.error $!.backtrace.join("\n")
          Cougaar.logger.info "GLS Connection Closed"
        end
      end
    end
    
    def wait_for_next_stage
      @next_stage_count += 1
puts "Waiting for stage: #{@next_stage_count}"
      while @next_stage_count != @stages.size
        sleep 2
      end
    end
    
    def auto_publish_gls
      result = Cougaar::Communications::HTTP.get("#{@run.society.agents['NCA'].uri}/glsinit?command=publishgls&oplanID=#{@oplan_id}&c0_date=#{@c0_date}")
    end

    def can_send_oplan?
      @can_send_oplan
    end
    
    def gls_connected?
      @gls_connected
    end
    
    def close
      begin
        @gls_connection.finish
        @gls_thread.kill if @gls_thread
      rescue
        Cougaar.logger.error "Error shutting down gls connection"
        Cougaar.logger.error $!
        Cougaar.logger.error $!.backtrace.join("\n")
      end
    end

  end
end

module Cougaar  
  module States
  
    class OPlanReady < Cougaar::State
      DEFAULT_TIMEOUT = 30.minutes
      PRIOR_STATES = ["SocietyRunning"]
      DOCUMENTATION = Cougaar.document {
        @description = "Waits for the OPlan ready Cougaar Event."
        @parameters = [
          {:timeout => "default=nil, Amount of time to wait in seconds."},
          {:block => "The timeout handler (unhandled: StopSociety, StopCommunications"}
        ]
        @example = "
          wait_for 'OPlanReady', 2.hours do
            puts 'Did not get OPlanReady!!!'
            do_action 'StopSociety'
            do_action 'StopCommunications'
          end
        "
      }
      def initialize(run, timeout=nil, &block)
        super(run, timeout, &block)
      end
      
      def process
        loop = true
        while loop
          event = @run.get_next_event
          if event.event_type=="STATUS" && event.cluster_identifier=="NCA" && event.component=="OPlanDetector"
            loop = false
          end
        end
        gls_client = ::UltraLog::GLSClient.new(run)
        @run['gls_client'] = gls_client
        until gls_client.can_send_oplan?
          sleep 2
        end
      end
      
      def unhandled_timeout
        @run.do_action "StopSociety" 
        @run.do_action "StopCommunications"
      end
    end

    class GLSConnection < Cougaar::State
      DEFAULT_TIMEOUT = 30.minutes
      PRIOR_STATES = ["SocietyRunning"]
      DOCUMENTATION = Cougaar.document {
        @description = "Waits for the GLS connection."
        @parameters = [
          {:timeout => "default=nil, Amount of time to wait in seconds."},
          {:block => "The timeout handler (unhandled: StopSociety, StopCommunications"}
        ]
        @example = "
          wait_for 'GLSConnection'
        "
      }
      def initialize(run, timeout=nil, &block)
        super(run, timeout, &block)
      end
      
      def process
        gls_client = ::UltraLog::GLSClient.new(run)
        @run['gls_client'] = gls_client
        until gls_client.can_send_oplan?
          sleep 2
        end
        begin
          result = Cougaar::Communications::HTTP.get("#{@run.society.agents['NCA'].uri}/glsinit?command=getopinfo")
          raise_failure "Error sending OPlan" unless result
        rescue
          puts $!
          puts $!.backtrace.join
        end
      end
      
      def unhandled_timeout
        @run.do_action "StopSociety" 
        @run.do_action "StopCommunications"
      end
    end
    
    class NextOPlanStage < Cougaar::State
      DEFAULT_TIMEOUT = 30.minutes
      PRIOR_STATES = ["SocietyRunning"]
      DOCUMENTATION = Cougaar.document {
        @description = "Waits for the OPlan stage."
        @parameters = [
          {:timeout => "default=nil, Amount of time to wait in seconds."},
          {:block => "The timeout handler (unhandled: StopSociety, StopCommunications"}
        ]
        @example = "
          wait_for 'NextOPlanStage'
        "
      }
      def initialize(run, timeout=nil, &block)
        super(run, timeout, &block)
      end
      
      def process
        gls_client = @run['gls_client']
        gls_client.wait_for_next_stage
      end
      
      def unhandled_timeout
        @run.do_action "StopSociety" 
        @run.do_action "StopCommunications"
      end
    end
    
    class GLSReady < Cougaar::State
      DEFAULT_TIMEOUT = 30.minutes
      PRIOR_STATES = ["OPlanSent"]
      DOCUMENTATION = Cougaar.document {
        @description = "DEPRECATED: Waits for the GLS ready Cougaar Event."
        @parameters = [
          {:timeout => "default=nil, Amount of time to wait in seconds."},
          {:block => "The timeout handler (unhandled: StopSociety, StopCommunications)"}
        ]
      }
      
      def initialize(run, timeout=nil, &block)
        super(run, timeout, &block)
      end
      
      def process
        puts "WARNING: This state is deprecated."
        #loop = true
        #while loop
        #  event = @run.get_next_event
        #  if event.event_type=="STATUS" && event.cluster_identifier=="5-CORPS" && event.component=="OPlanDetector"
        #    loop = false
        #  end
        #end
        #gls_client = @run['gls_client']
        #until gls_client.gls_connected?
        #  sleep 2
        #end
      end
      
      def unhandled_timeout
        @run.do_action "StopSociety"
        @run.do_action "StopCommunications"
      end
    end
    
    class PlanningComplete < Cougaar::State
      DEFAULT_TIMEOUT = 60.minutes
      PRIOR_STATES = ["SocietyPlanning"]
      DOCUMENTATION = Cougaar.document {
        @description = "Waits for the Planning Complete Cougaar Event."
        @parameters = [
          {:timeout => "default=nil, Amount of time to wait in seconds."},
          {:block => "The timeout handler (unhandled: StopSociety, StopCommunications)"}
        ]
        @example = "
          wait_for 'PlanningComplete', 2.hours do
            puts 'Did not get Planning Complete!!!'
            do_action 'StopSociety'
            do_action 'StopCommunications'
          end
        "
      }
      
      def initialize(run, timeout=nil, &block)
        super(run, timeout, &block)
      end
      
      def process
        loop = true
        while loop
          event = @run.get_next_event
          if event.data.include?("Planning Complete")
            loop = false
          end
        end
      end
      
      def unhandled_timeout
        @run.do_action "StopSociety"
        @run.do_action "StopCommunications"
      end
    end
    
    class PlanningActive < Cougaar::State
      DEFAULT_TIMEOUT = 60.minutes
      PRIOR_STATES = ["PlanningComplete"]
      DOCUMENTATION = Cougaar.document {
        @description = "Waits for the Planning Active Cougaar Event."
        @parameters = [
          {:timeout => "default=nil, Amount of time to wait in seconds."},
          {:block => "The timeout handler (unhandled: StopSociety, StopCommunications)"}
        ]
        @example = "
          wait_for 'PlanningActive', 10.minutes do
            puts 'Did not get Planning Active!!!'
            do_action 'StopSociety'
            do_action 'StopCommunications'
          end
        "
      }
      
      def initialize(run, timeout=nil, &block)
        super(run, timeout, &block)
      end
      
      def process
        loop = true
        while loop
          event = @run.get_next_event
          if event.data.include?("Planning Active")
            loop = false
          end
        end
      end
      
      def unhandled_timeout
        @run.do_action "StopSociety"
        @run.do_action "StopCommunications"
      end
    end
    
    class OPlanSent < Cougaar::NOOPState
      DOCUMENTATION = Cougaar.document {
        @description = "Indicates that the OPlan was sent."
      }
    end
    
    class SocietyPlanning < Cougaar::NOOPState
      DOCUMENTATION = Cougaar.document {
        @description = "Indicates that the society is planning."
      }
    end
      
  end
  
  module Actions
  
    class RehydrateSociety < Cougaar::Action
      PRIOR_STATES = ["SocietyRunning"]
      RESULTANT_STATE = "SocietyPlanning"
      DOCUMENTATION = Cougaar.document {
        @description = "This action is used in place of OPlan/GLS actions if you start a society from a persistent state."
        @example = "do_action 'RehydrateSociety'"
      }
      def perform
      end
    end

    class SendOPlan < Cougaar::Action
      PRIOR_STATES = ["OPlanReady"]
      RESULTANT_STATE = "OPlanSent"
      DOCUMENTATION = Cougaar.document {
        @description = "Sends the OPlan to the glsinit servlet."
        @example = "do_action 'SendOPlan'"
      }
      def perform
        begin
          result = Cougaar::Communications::HTTP.get("#{@run.society.agents['NCA'].uri}/glsinit?command=sendoplan")
          raise_failure "Error sending OPlan" unless result
        rescue
          raise_failure "Could not send OPlan", $!
        end
      end
    end

    class PublishNextStage < Cougaar::Action
      PRIOR_STATES = ["NextOPlanStage"]
      RESULTANT_STATE = "SocietyPlanning"
      DOCUMENTATION = Cougaar.document {
        @description = "Publishes the next stage of the GLS root task to the glsinit servlet."
        @example = "do_action 'PublishNextStage'"
      }
      
      def perform
        gls_client = @run['gls_client']
        begin
          result = Cougaar::Communications::HTTP.get("#{@run.society.agents['NCA'].uri}/glsinit?command=publishgls&oplanID=#{gls_client.oplan_id}&c0_date=#{gls_client.c0_date}")
          raise_failure "Error publishing next stage" unless result
        rescue
          raise_failure "Could not publish next stage", $!
        end
      end
    end
    
    class PublishGLSRoot < Cougaar::Action
      PRIOR_STATES = ["OPlanSent"]
      RESULTANT_STATE = "SocietyPlanning"
      DOCUMENTATION = Cougaar.document {
        @description = "Publishes the GLS root task to the glsinit servlet."
        @example = "do_action 'PublishGLSRoot'"
      }
      def perform
      
        gls_client = @run['gls_client']
        until gls_client.gls_connected?
          sleep 2
        end

        begin
          if gls_client.c0_date
            result = Cougaar::Communications::HTTP.get("#{@run.society.agents['NCA'].uri}/glsinit?command=publishgls&oplanID=#{gls_client.oplan_id}&c0_date=#{gls_client.c0_date}")
          else
            result = Cougaar::Communications::HTTP.get("#{@run.society.agents['NCA'].uri}/glsinit?command=publishgls&oplanID=#{gls_client.oplan_id}")
          end
          raise_failure "Error publishing OPlan" unless result
        rescue
          raise_failure "Could not publish OPlan", $!
        ensure
          gls_client.close
        end
      end
    end
  end
end
