CarrierWave.configure do |config|
  #if Rails.env.staging? || Rails.env.production?
    #config.fog_provider = "fog/aws" 
    config.fog_credentials = {
      :provider => "AWS",
      :aws_access_key_id => "AKIARM4ZEEKGHAQFQWWA",
      :aws_secret_access_key => "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",
      :region => "eu-west-1" # Ireland
    }
    config.fog_directory = "toppin"
    config.storage = :fog

    


 # else
  #  config.storage = :file
#    config.enable_processing = Rails.env.development?
#  end
end