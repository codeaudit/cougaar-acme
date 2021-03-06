##
#  <copyright>
#  Copyright 2002-2004 InfoEther, LLC & BBN Technologies, LLC
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

module Cougaar; module Actions
    class DisableNetworkInterfaces < Cougaar::Action
      PRIOR_STATES = ["SocietyLoaded"]
      DOCUMENTATION = Cougaar.document {
        @description = "Disables the NIC one or more nodes' hosts."
        @parameters = [
          {:nodes=> "required, List of node names."}
        ]
        @example = "do_action 'DisableNetworkInterfaces', 'TRANSCOM-NODE', 'CONUS-NODE'"
      }
      def initialize(run, *nodes)
        super(run)
        @nodes = nodes
      end
      def perform
        net = run['network']
        @nodes.each do |node|
          cougaar_node = @run.society.nodes[node]
          cougaar_host = cougaar_node.host
          node_names = cougaar_host.nodes.collect { |node| node.name }
                    
          @run.info_message "Taking down network for host #{cougaar_host.name} that has nodes #{node_names.join(', ')}"
          if cougaar_node
            if (net && net.migratory_active_subnet.has_key?(cougaar_node.host)) then
              subnet = net.subnet[net.migratory_active_subnet[cougaar_node.host]]
              result = @run.comms.new_message(cougaar_node.host).set_body("command[net]disable(#{subnet.make_interface(cougaar_node.host.get_facet(:interface))})").send(30)
              puts "#{result.body}" unless result.nil?
            else
              @run.comms.new_message(cougaar_node.host).set_body("command[nic]trigger").send
            end
          else
            raise_failure "Cannot disable nic on node #{node}, node unknown."
          end
        end
      end
      def to_s
        return super.to_s + "(#{@nodes.join(', ')})"
      end
    end

    class EnableNetworkInterfaces < Cougaar::Action
      PRIOR_STATES = ["SocietyLoaded"]
      DOCUMENTATION = Cougaar.document {
        @description = "Enables the NIC one or more nodes' hosts."
        @parameters = [
          {:nodes=> "required, List of node names."}
        ]
        @example = "do_action 'EnableNetworkInterfaces', 'TRANSCOM-NODE', 'CONUS-NODE'"
      }
      def initialize(run, *nodes)
        super(run)
        @nodes = nodes
      end
      def perform
        net = @run['network']
        @nodes.each do |node|
          cougaar_node = @run.society.nodes[node]
          if cougaar_node
            if (net && net.migratory_active_subnet.has_key?(cougaar_node.host)) then
              subnet = net.subnet[net.migratory_active_subnet[cougaar_node.host]]
              @run.comms.new_message(cougaar_node.host).set_body("command[net]enable(#{subnet.make_interface(cougaar_node.host.get_facet(:interface))})").send(30)
            else
              @run.comms.new_message(cougaar_node.host).set_body("command[nic]reset").send
            end
          else
            raise_failure "Cannot enable nic on node #{node}, node unknown."
          end
        end
      end
      def to_s
        return super.to_s + "(#{@nodes.join(', ')})"
      end
    end

    class IntermittentNetworkInterfaces < CyclicStress
      PRIOR_STATES = ["SocietyLoaded"]
      DOCUMENTATION = Cougaar.document {
        @description = "Disables the NIC one or more nodes' hosts."
        @parameters = [
          {:handle => "required, Handle to refer to the intermittent thread.",
           :on_time => "required, Amount of time stressor is on.",
           :off_time => "required, Amount of time stressor is off.",
           :nodes=> "required, List of node names."}
        ]
        @example = "do_action 'IntermittentNetworkInterfaces', 'IN-001', 1.second, 1.second, 'TRANSCOM-NODE', 'CONUS-NODE'"
      }
      def initialize(run, handle, on_time, off_time, *nodes)
        super(run, handle, on_time, off_time)
        @nodes = nodes
      end

      def perform
        @nodes.each do |node|
          cougaar_node = @run.society.nodes[node]
          cougaar_host = cougaar_node.host
          node_names = cougaar_host.nodes.collect { |node| node.name }
                    
          @run.info_message "Setting up intermittent network for host #{cougaar_host.name} that has nodes #{node_names.join(', ')}"
        end
        super
      end

      def stress_on
        @nodes.each do |node|
          cougaar_node = @run.society.nodes[node]
          if cougaar_node
            @run.comms.new_message(cougaar_node.host).set_body("command[nic]trigger").send
          else
            raise_failure "Cannot disable nic on node #{node}, node unknown."
          end
        end
      end

      def stress_off
        @nodes.each do |node|
           cougaar_node = @run.society.nodes[node]
           if cougaar_node
             @run.comms.new_message(cougaar_node.host).set_body("command[nic]reset").send
           else
             raise_failure "Cannot enable nic on node #{node}, node unknown."
           end
        end
      end

      def to_s
        return super.to_s + "(#{@nodes.join(', ')})"
      end
    end

    class StressCPU < Cougaar::Action
      PRIOR_STATES = ["SocietyLoaded"]
      DOCUMENTATION = Cougaar.document {
        @description = "Starts or stops the CPU stressor on one or more hosts."
        @parameters = [
          {:percent=> "required, The percentage of CPU stress to apply."},
          {:hosts=> "optional, The comma-separated list of hosts to stress.  If omitted, all hosts are stressed."}
        ]
        @example = "do_action 'StressCPU', 20, 'sb022,sb023'"
      }

      def initialize(run, percent, hosts = nil)
        super(run)
        @percent = percent
        if hosts
          @hosts = hosts.split(",")
        end
      end

      def perform
        unless @hosts
          @hosts = []
          @run.society.each_service_host("acme") do |host|
            @hosts << host.name
          end
          @hosts.uniq!
        end
        
        cmd = "command[cpu]#{@percent}"
        @hosts.each do |host|
          cougaar_host = run.society.hosts[host]
          @run.comms.new_message(cougaar_host).set_body(cmd).send if cougaar_host
        end
      end
    end
  end
end
