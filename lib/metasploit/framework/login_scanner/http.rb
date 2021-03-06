require 'rex/proto/http'
require 'metasploit/framework/login_scanner/base'
require 'metasploit/framework/login_scanner/rex_socket'

module Metasploit
  module Framework
    module LoginScanner
      #
      # HTTP-specific login scanner.
      #
      class HTTP
        include Metasploit::Framework::LoginScanner::Base
        include Metasploit::Framework::LoginScanner::RexSocket

        DEFAULT_REALM        = nil
        DEFAULT_PORT         = 80
        DEFAULT_SSL_PORT     = 443
        LIKELY_PORTS         = [ 80, 443, 8000, 8080 ]
        LIKELY_SERVICE_NAMES = [ 'http', 'https' ]
        PRIVATE_TYPES        = [ :password ]
        REALM_KEY            = Metasploit::Model::Realm::Key::ACTIVE_DIRECTORY_DOMAIN

        # @!attribute uri
        #   @return [String] The path and query string on the server to
        #     authenticate to.
        attr_accessor :uri

        # @!attribute uri
        #   @return [String] HTTP method, e.g. "GET", "POST"
        attr_accessor :method

        validates :uri, presence: true, length: { minimum: 1 }

        validates :method,
                  presence: true,
                  length: { minimum: 1 }

        # Attempt a single login with a single credential against the target.
        #
        # @param credential [Credential] The credential object to attempt to
        #   login with.
        # @return [Result] A Result object indicating success or failure
        def attempt_login(credential)
          ssl = false if ssl.nil?

          result_opts = {
            credential: credential,
            status: Metasploit::Model::Login::Status::INCORRECT,
            proof: nil,
            host: host,
            port: port,
            protocol: 'tcp'
          }

          if ssl
            result_opts[:service_name] = 'https'
          else
            result_opts[:service_name] = 'http'
          end

          http_client = Rex::Proto::Http::Client.new(
            host, port, {}, ssl, ssl_version,
            nil, credential.public, credential.private
          )
          if credential.realm
            http_client.set_config('domain' => credential.realm)
          end

          begin
            http_client.connect
            request = http_client.request_cgi(
              'uri' => uri,
              'method' => method
            )

            # First try to connect without logging in to make sure this
            # resource requires authentication. We use #_send_recv for
            # that instead of #send_recv.
            response = http_client._send_recv(request)
            if response && response.code == 401 && response.headers['WWW-Authenticate']
              # Now send the creds
              response = http_client.send_auth(
                response, request.opts, connection_timeout, true
              )
              if response && response.code == 200
                result_opts.merge!(status: Metasploit::Model::Login::Status::SUCCESSFUL, proof: response.headers)
              end
            else
              result_opts.merge!(status: Metasploit::Model::Login::Status::NO_AUTH_REQUIRED)
            end
          rescue ::EOFError, Rex::ConnectionError, ::Timeout::Error
            result_opts.merge!(status: Metasploit::Model::Login::Status::UNABLE_TO_CONNECT)
          ensure
            http_client.close
          end

          Result.new(result_opts)
        end

        private

        # This method sets the sane defaults for things
        # like timeouts and TCP evasion options
        def set_sane_defaults
          self.connection_timeout ||= 20
          self.max_send_size = 0 if self.max_send_size.nil?
          self.send_delay = 0 if self.send_delay.nil?
          self.uri = '/' if self.uri.blank?
          self.method = 'GET' if self.method.blank?

          # Note that this doesn't cover the case where ssl is unset and
          # port is something other than a default. In that situtation,
          # we don't know what the user has in mind so we have to trust
          # that they're going to do something sane.
          if !(self.ssl) && self.port.nil?
            self.port = self.class::DEFAULT_PORT
            self.ssl = false
          elsif self.ssl && self.port.nil?
            self.port = self.class::DEFAULT_SSL_PORT
          elsif self.ssl.nil? && self.port == self.class::DEFAULT_PORT
            self.ssl = false
          elsif self.ssl.nil? && self.port == self.class::DEFAULT_SSL_PORT
            self.ssl = true
          end

          nil
        end

      end
    end
  end
end
