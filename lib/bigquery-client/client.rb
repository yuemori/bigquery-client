require 'json'
require 'google/api_client'
require 'google/api_client/client_secrets'
require 'google/api_client/auth/installed_app'
require 'google/api_client/auth/compute_service_account'

module BigQuery
  class Client
    include BigQuery::Datasets
    include BigQuery::Jobs
    include BigQuery::Projects
    include BigQuery::Tabledata
    include BigQuery::Tables

    private

    def initialize(attributes = {})
      attributes.each { |name, value| instance_variable_set("@#{name}", value) }
    end

    def access_api(params = {})
      params[:parameters] ||= {}
      params[:parameters][:projectId] ||= @project
      params[:parameters][:datasetId] ||= @dataset
      result = client.execute(params)
      handle_error(result) if result.error?
      JSON.parse(result.body) unless result.body.empty?
    end

    def bigquery
      @bigquery ||= client.discovered_api('bigquery', 'v2')
    end

    def handle_error(result)
      @client = nil
      error =
        case result.status
        when 404      then NotFound
        when 409      then Conflict
        when 400..499 then ClientError
        when 500..599 then ServerError
        else UnexpectedError
        end
      fail error, result.error_message
    end

    def client
      @client = nil if expired?
      unless @client
        @client = Google::APIClient.new(
          application_name:    'bigquery-client',
          application_version: BigQuery::Client::VERSION
        )
        authorize_client
        @expiration = Time.now + 1800
      end
      @client
    end

    def expired?
      @expiration && @expiration < Time.now
    end

    def authorize_client
      case @auth_method
      when 'private_key'
        asserter = Google::APIClient::JWTAsserter.new(
          @email,
          'https://www.googleapis.com/auth/bigquery',
          Google::APIClient::PKCS12.load_key(@private_key_path, @private_key_passphrase)
        )
        @client.authorization = asserter.authorize
      when 'compute_engine'
        auth = Google::APIClient::ComputeServiceAccount.new
        auth.fetch_access_token!
        @client.authorization = auth
      when 'client_secrets'
        file_storage = Google::APIClient::Storage.new(Google::APIClient::FileStore.new(@credential_store_file))
        auth = file_storage.authorize

        if file_storage.authorization.nil?
          client_secrets = Google::APIClient::ClientSecrets.load(@client_secrets_path)
          flow = Google::APIClient::InstalledAppFlow.new(
            client_id: client_secrets.client_id,
            client_secret: client_secrets.client_secret,
            scope: 'https://www.googleapis.com/auth/bigquery'
          )

          auth = flow.authorize(file_storage)
        end
        @client.authorization = auth
      end
    end
  end
end
