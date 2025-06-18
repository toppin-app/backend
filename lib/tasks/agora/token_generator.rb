# app/lib/agora/token_generator.rb
require 'agora_dynamic_key'

module Agora
  class TokenGenerator
    APP_ID = ENV.fetch("AGORA_APP_ID")
    APP_CERTIFICATE = ENV.fetch("AGORA_APP_CERTIFICATE")
    TOKEN_EXPIRATION = 60 # seconds

    def self.generate(channel:, uid:)
      current_timestamp = Time.now.to_i
      expire_timestamp = current_timestamp + TOKEN_EXPIRATION

      AgoraDynamicKey::RtcTokenBuilder.build_token_with_uid(
        APP_ID,
        APP_CERTIFICATE,
        channel,
        uid,
        AgoraDynamicKey::RtcTokenBuilder::Role::PUBLISHER,
        expire_timestamp
      )
    end
  end
end
