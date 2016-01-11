#!/usr/bin/env ruby
#
# October 2015, Glenn F. Matthews
#
# Copyright (c) 2015 Cisco and/or its affiliates.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

require_relative 'client_errors'
require_relative '../constants'
require_relative '../logger'

include Cisco::Logger

# Base class for clients of various RPC formats
class Cisco::Client
  @@clients = [] # rubocop:disable Style/ClassVars

  def self.clients
    @@clients
  end

  # Each subclass should call this method to register itself.
  def self.register_client(client)
    @@clients << client
  end

  attr_reader :data_formats, :platform

  def initialize(address:      nil,
                 username:     nil,
                 password:     nil,
                 data_formats: [],
                 platform:     nil)
    if self.class == Cisco::Client
      fail NotImplementedError, 'Cisco::Client is an abstract class. ' \
        "Instantiate one of #{@@clients} or use Cisco::Client.create() instead"
    end
    validate_args(address, username, password)
    @address = address
    @username = username
    @password = password
    self.data_formats = data_formats
    self.platform = platform
    @cache_enable = true
    @cache_auto = true
    cache_flush
  end

  def validate_args(address, username, password)
    unless address.nil?
      fail TypeError, 'invalid address' unless address.is_a?(String)
      fail ArgumentError, 'empty address' if address.empty?
    end
    unless username.nil?
      fail TypeError, 'invalid username' unless username.is_a?(String)
      fail ArgumentError, 'empty username' if username.empty?
    end
    unless password.nil? # rubocop:disable Style/GuardClause
      fail TypeError, 'invalid password' unless password.is_a?(String)
      fail ArgumentError, 'empty password' if password.empty?
    end
  end

  def supports?(data_format)
    data_formats.include?(data_format)
  end

  # Try to create an instance of an appropriate subclass
  def self.create(address=nil, username=nil, password=nil)
    fail 'No client implementations available!' if clients.empty?
    debug "Trying to establish client connection. clients = #{clients}"
    errors = []
    clients.each do |client_class|
      begin
        debug "Trying to connect to #{address} as #{client_class}"
        client = client_class.new(address, username, password)
        debug "#{client_class} connected successfully"
        return client
      rescue ClientError, TypeError, ArgumentError => e
        debug "Unable to connect to #{address} as #{client_class}: #{e.message}"
        debug e.backtrace.join("\n  ")
        errors << e
      end
    end
    handle_errors(errors)
  end

  def self.handle_errors(errors)
    # ClientError means we tried to connect but failed,
    # so it's 'more significant' than input validation errors.
    client_errors = errors.select { |e| e.kind_of? ClientError }
    if !client_errors.empty?
      # Reraise the specific error if just one
      fail client_errors[0] if client_errors.length == 1
      # Otherwise clump them together into a new error
      e_cls = client_errors[0].class
      e_cls = ClientError unless client_errors.all? { |e| e.class == e_cls }
      fail e_cls, ("Unable to establish any client connection:\n" +
                   errors.each(&:message).join("\n"))
    elsif errors.any? { |e| e.kind_of? ArgumentError }
      fail ArgumentError, ("Invalid arguments:\n" +
                           errors.each(&:message).join("\n"))
    elsif errors.any? { |e| e.kind_of? TypeError }
      fail TypeError, ("Invalid arguments:\n" +
                       errors.each(&:message).join("\n"))
    end
    fail ClientError, 'No client connected, but no errors were reported?'
  end

  def to_s
    @address.to_s
  end

  def inspect
    "<#{self.class} of #{@address}>"
  end

  def cache_enable?
    @cache_enable
  end

  def cache_enable=(enable)
    @cache_enable = enable
    cache_flush unless enable
  end

  def cache_auto?
    @cache_auto
  end

  attr_writer :cache_auto

  # Clear the cache of CLI output results.
  #
  # If cache_auto is true (default) then this will be performed automatically
  # whenever a config() is called, but providers may also call this
  # to explicitly force the cache to be cleared.
  def cache_flush
    # to be implemented by subclasses
  end

  # Configure the given command(s) on the device.
  #
  # @raise [RequestFailed] if the configuration fails
  #
  # @param commands [String, Array<String>] either of:
  #   1) The configuration sequence, as a newline-separated string
  #   2) An array of command strings (one command per string, no newlines)
  def config(commands) # rubocop:disable Lint/UnusedMethodArgument
    cache_flush if cache_auto?
    # to be implemented by subclasses
  end

  # Executes a "show" command on the device, returning either ASCII or
  # structured output.
  #
  # Unlike config() this will not clear the CLI cache;
  # multiple calls to the same "show" command may return cached data
  # rather than querying the device repeatedly.
  #
  # @raise [RequestNotSupported] if
  #   structured output is requested but the given command can't provide it.
  # @raise [RequestFailed] if the command is rejected by the device
  #
  # @param command [String] the show command to execute
  # @param type [:ascii, :structured] ASCII or structured output.
  #             Default is :ascii
  # @return [String] the output of the show command, if type == :ascii
  # @return [Hash{String=>String}] key-value pairs, if type == :structured
  def show(command, type=:ascii)
    # to be implemented by subclasses
  end

  private

  # List of data formats supported by this client.
  # If the client supports multiple formats, and a given feature or property
  # can be managed by multiple formats, the list order indicates preference.
  def data_formats=(data_formats)
    data_formats = [data_formats] unless data_formats.is_a?(Array)
    unknown = data_formats - Cisco::DATA_FORMATS
    fail ArgumentError, "unknown data formats: #{unknown}" unless unknown.empty?
    @data_formats = data_formats
  end

  def platform=(platform)
    fail ArgumentError, "unknown platform #{platform}" \
      unless Cisco::PLATFORMS.include?(platform)
    @platform = platform
  end
end
