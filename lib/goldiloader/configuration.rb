module Goldiloader
  def self.configuration
    @configuration ||= Configuration.new
  end

  def self.configure
    yield(configuration)
  end

  class Configuration
    attr_accessor :auto_include

    def initialize
      @auto_include = true
    end
  end
end
