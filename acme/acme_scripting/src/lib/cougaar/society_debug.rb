

module Cougaar
  module Actions
    class EnableDebugging < Cougaar::Action
      DOCUMENTATION = Cougaar.document {
        @description = "Enable debugging of society JVMs."
        @example = "do_action 'EnableDebugging'"
      }
      
      def perform
        @run.society.each_host do |host|
          port = 7744
          host.each_node do |node|
            node.replace_parameter(/runjdwp/, "-Xdebug -Xnoagent -Djava.compiler=NONE -Xrunjdwp:transport=dt_socket,address=#{port},server=y,suspend=n")
            node.add_facet { |facet| facet[:debug_port] = port }
            port += 1
          end
        end
      end
    end

    class StartDebugging < Cougaar::Action
      DOCUMENTATION = Cougaar.document {
        @description = "Start debugging of society by connecting to JVMs."
        @example = "do_action 'StartDebugging'"
      }
      
      def perform
        sessions = {}
        @run[:debug_sessions] = sessions
        @run.society.each_node do |node|
          session = Session.new
          session.transport = SocketTransport.new(node.host.uri_name, node.get_facet("debug_port"))
          session.start
          sessions[node.name] = session
        end
      end
    end
    
    class SuspendSociety < Cougaar::Action
      DOCUMENTATION = Cougaar.document {
        @description = "Suspend all threads in all society JVMs."
        @example = "do_action 'SuspendSociety'"
      }
      
      def perform
        sessions = @run[:debug_sessions]
        sessions.each do |node_name, session|
          session.send(Packets::VirtualMachine::Suspend.new)
        end
      end
    end

    class ResumeSociety < Cougaar::Action
      DOCUMENTATION = Cougaar.document {
        @description = "Resume all threads in all society JVMs."
        @example = "do_action 'ResumeSociety'"
      }
      
      def perform
        sessions = @run[:debug_sessions]
        sessions.each do |node_name, session|
          session.send(Packets::VirtualMachine::Resume.new)
        end
      end
    end

    class StopDebugging < Cougaar::Action
      DOCUMENTATION = Cougaar.document {
        @description = "Stop all debugging sessions."
        @example = "do_action 'StopDebugging'"
      }
      
      def perform
        sessions = @run[:debug_sessions]
        sessions.each do |node_name, session|
          session.close
        end
        @run[:debug_sessions] = {}
      end
    end
    
  end
end


