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

        Rails.logger.info "______________________________"
        Rails.logger.info msg.inspect
        Rails.logger.info _worker.inspect
        Registry.get msg["class"] do |strategy|
          strategy.finalize!(msg["jid"], *msg["args"])
        end
      end
    end
  end
end
