class ApplicationMailer < ActionMailer::Base
  default from: ENV['MAILJET_FROM_EMAIL'] || 'noreply@tudominio.com',
          reply_to: ENV['MAILJET_FROM_EMAIL'] || 'noreply@tudominio.com'
  
  layout 'mailer'
end
