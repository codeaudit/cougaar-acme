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

$:.unshift ".." if $0 == __FILE__

require 'cgi'
require 'cougaar/communications'
require 'cougaar/state_action'

module Cougaar
  module Actions
    class GLMStimulator < Cougaar::Action
      RESULTANT_STATE = 'SocietyPlanning'
      def initialize(run, agent, &block)
        super(run)
        @agent = @run.society.agents[agent]
        @action = block
      end
      def perform
        @action.call(::UltraLog::GLMStimulator.for_cougaar_agent(@agent))
      end
    end
  end
end

module UltraLog

  ##
  # The Completion class wraps access the data generated by the completion servlet
  #
  class GLMStimulator
  
    attr_accessor :inputFileName, :forPrep, :numberOfBatches, :tasksPerBatch,
                  :interval, :waitBefore, :waitAfter, :rescindAfterComplete, 
                  :useConfidence, :format
                  
    def initialize(agent, host)
      @agent = agent
      @host = host
      @inputFileName = ""
      @forPrep = ""
      @format = "html"
      query_defaults
      yield self if block_given?
    end
    
    def self.for_agent_on_host(agent, host)
      return self.new(agent, host)
    end
    
    def self.for_cougaar_agent(agent)
      return self.new(agent.name, agent.node.host.host_name)
    end
    
    def update(format = nil)
      @format = format.to_s if format
      params = get_params
      result = Cougaar::Communications::HTTP.get("http://#{@host}:8800/$#{@agent}/stimulator?#{params.join('&')}", 300)
      raise "Unable to update values in GLMStimulator" unless result
      return result[0]
    end
    
    def to_s
      get_params.join("\n")
    end
    
    private
    
    def get_params
      params = []
      params << "inputFileName=#{CGI.escape(@inputFileName)}"
      params << "forPrep=#{CGI.escape(@forPrep)}"
      params << "numberOfBatches=#{@numberOfBatches}"
      params << "tasksPerBatch=#{@tasksPerBatch}"
      params << "interval=#{@interval}"
      params << "waitBefore=#{@waitBefore}" if @waitBefore
      params << "waitAfter=#{@waitAfter}" if @waitAfter
      params << "rescindAfterComplete=#{@rescindAfterComplete}" if @rescindAfterComplete
      params << "useConfidence=#{@useConfidence}" if @useConfidence
      params << "format=#{@format}"
      params << "submit=Inject"
      params
    end
    
    def query_defaults
      value = /VALUE="(\w+)"/
      data = Cougaar::Communications::HTTP.get("http://#{@host}:8800/$#{@agent}/stimulator", 300)
      raise "Unable to query default values in GLMStimulator" unless data
      values = data[0].scan(value)
      @numberOfBatches = values[0][0].to_i
      @tasksPerBatch = values[1][0].to_i
      @interval = values[2][0].to_i
      @waitBefore = false
      @waitAfter = false
      @rescindAfterComplete = false
      @useConfidence = false
    end
    
  end
  
end

if $0==__FILE__
  stimulator = UltraLog::GLMStimulator.for_agent_on_host("1-35-ARBN", "u192")
  stimulator.inputFileName="Supply.dat.xml"
  puts stimulator.update(:xml)
end
