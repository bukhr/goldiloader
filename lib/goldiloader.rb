# frozen_string_literal: true

require 'active_support/all'
require 'active_record'
require 'goldiloader/compatibility'
require 'goldiloader/auto_include_context'
require 'goldiloader/scope_info'
require 'goldiloader/association_options'
require 'goldiloader/association_loader'
require 'goldiloader/active_record_patches'

module Goldiloader
  class << self
    attr_accessor :auto_preload

    def auto_include
      Goldiloader.configuration.auto_include || auto_preload
    end
  end

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
