# frozen_string_literal: true

# 3rd party
require "sidekiq"

# internal
require_relative "./throttled/version"
require_relative "./throttled/configuration"
require_relative "./throttled/fetch"
require_relative "./throttled/registry"
require_relative "./throttled/job"
require_relative "./throttled/middleware"
require_relative "./throttled/worker"
require_relative "./throttled/utils"

# @see https://github.com/mperham/sidekiq/
module Sidekiq
  # Concurrency and threshold throttling for Sidekiq.
  #
  # Just add somewhere in your bootstrap:
  #
  #     require "sidekiq/throttled"
  #     Sidekiq::Throttled.setup!
  #
  # Once you've done that you can include {Sidekiq::Throttled::Job} to your
  # job classes and configure throttling:
  #
  #     class MyJob
  #       include Sidekiq::Job
  #       include Sidekiq::Throttled::Job
  #
  #       sidekiq_options :queue => :my_queue
  #
  #       sidekiq_throttle({
  #         # Allow maximum 10 concurrent jobs of this class at a time.
  #         :concurrency => { :limit => 10 },
  #         # Allow maximum 1K jobs being processed within one hour window.
  #         :threshold => { :limit => 1_000, :period => 1.hour }
  #       })
  #
  #       def perform
  #         # ...
  #       end
  #     end
  module Throttled
    MUTEX = Mutex.new
    private_constant :MUTEX

    class << self
      include Utils

      # @return [Configuration]
      def configuration
        @configuration ||= Configuration.new
      end

      # Hooks throttler into sidekiq.
      #
      # @return [void]
      def setup!
        Sidekiq.configure_server do |config|
          if Gem::Version.new("7.0.0") <= Gem::Version.new(Sidekiq::VERSION)
            config[:fetch_class] = Sidekiq::Throttled::Fetch
          else
            config[:fetch] = Sidekiq::Throttled::Fetch.new(config)
          end
        end
      end

      # Tells whenever job is throttled or not.
      #
      # @param [String] message Job's JSON payload
      # @return [Boolean]
      def throttled?(message)
        message = JSON.parse message
        job = message.fetch("wrapped") { message.fetch("class") { return false } }
        jid = message.fetch("jid") { return false }

        preload_constant! job

        Registry.get job do |strategy|
          return strategy.throttled?(jid, *message["args"])
        end

        false
      rescue
        false
      end

      private

      # Tries to preload constant by it's name once.
      #
      # Somehow, sometimes, some classes are not eager loaded upon Rails init,
      # leading to throttling config not being registered prior job perform.
      # And that leaves us with concurrency limit + 1 situation upon Sidekiq
      # server restart (becomes normal after all Sidekiq processes handled
      # at leas onr job of that class).
      #
      # @return [void]
      def preload_constant!(job)
        MUTEX.synchronize do
          @preloaded      ||= {}
          @preloaded[job] ||= constantize(job) || true
        end
      end
    end
  end

  configure_server do |config|
    config.server_middleware do |chain|
      chain.add Sidekiq::Throttled::Middleware
    end
  end
end
