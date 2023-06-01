# frozen_string_literal: true

# internal
require "sidekiq/throttled/registry"

module Sidekiq
  module Throttled
    # Server middleware that notifies strategy that job was finished.
    #
    # @private
    class Middleware
      # Called within Sidekiq job processing
      def call(_worker, msg, _queue)
        yield
      ensure

        Sidekiq.logger.info "______________________________"
        Sidekiq.logger.info msg.inspect
        Sidekiq.logger.info _worker.inspect
        Registry.get msg["class"] do |strategy|
          strategy.finalize!(msg["jid"], *msg["args"])
        end
      end
    end
  end
end
