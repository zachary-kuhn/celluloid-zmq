module DCell
  # A node in a DCell cluster
  class Node
    include Celluloid
    attr_reader :id, :addr

    @nodes = {}
    @lock  = Mutex.new

    class << self
      include Enumerable

      # Return all available nodes in the cluster
      def all
        Directory.all.map do |node_id|
          find node_id
        end
      end

      # Iterate across all available nodes
      def each
        Directory.all.each do |node_id|
          yield find node_id
        end
      end

      # Find a node by its node ID
      def find(id)
        node = @lock.synchronize { @nodes[id] }
        return node if node

        addr = Directory[id]

        if addr
          if id == DCell.id
            node = DCell.me
          else
            node = Node.new(id, addr)
          end

          @lock.synchronize do
            @nodes[id] ||= node
            @nodes[id]
          end
        end
      end
      alias_method :[], :find
    end

    def initialize(id, addr)
      @id, @addr = id, addr
      @socket = nil
    end

    def finalize
      @socket.close if socket
    end

    # Obtain the node's 0MQ socket
    def socket
      return @socket if @socket

      @socket = DCell.zmq_context.socket(::ZMQ::PUSH)
      unless ::ZMQ::Util.resultcode_ok? @socket.connect @addr
        @socket.close
        @socket = nil
        raise "error connecting to #{addr}: #{::ZMQ::Util.error_string}"
      end

      @socket
    end

    # Find an actor registered with a given name on this node
    def find(name)
      request = Query.new(Thread.mailbox, name)
      send_message request

      response = receive do |msg|
        msg.respond_to?(:request_id) && msg.request_id == request.id
      end

      abort response.value if response.is_a? ErrorResponse
      response.value
    end
    alias_method :[], :find

    # Send a message to another DCell node
    def send_message(message)
      begin
        string = Marshal.dump(message)
      rescue => ex
        abort ex
      end

      unless ::ZMQ::Util.resultcode_ok? socket.send_string string
        raise "error sending 0MQ message: #{::ZMQ::Util.error_string}"
      end
    end
    alias_method :<<, :send_message

    # Friendlier inspection
    def inspect
      "#<DCell::Node[#{@id}] @addr=#{@addr.inspect}>"
    end
  end
end
