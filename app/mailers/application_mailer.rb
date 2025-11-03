class ApplicationMailer < ActionMailer::Base
  default from: ENV['MAILERSEND_FROM_EMAIL'] || 'noreply@tudominio.com',
          reply_to: ENV['MAILERSEND_FROM_EMAIL'] || 'noreply@tudominio.com'
  
  layout 'mailer'
end
