class NotificationLocalizer
  def self.for(user:, type:, params: {})
    Rails.logger.info "NotificationLocalizer: user.language=#{user.language.inspect}"
    locale = case user.language
             when 'es', :es, 'ES' then :es
             when 'en', :en, 'EN' then :en
             else I18n.default_locale
             end
    Rails.logger.info "NotificationLocalizer: locale=#{locale}"

    I18n.with_locale(locale) do
      # ¡AÑADE ESTA LÍNEA AQUÍ PARA DEFINIR 'image_url'!
      image_url = I18n.t("notifications.#{type}.image", default: nil) # <--- Esta es la línea que falta

      {
        title: I18n.t("notifications.#{type}.title", **params),
        body: I18n.t("notifications.#{type}.body", **params),
        image: image_url # Ahora 'image_url' ya está definida cuando se usa aquí
      }
    end
  end
end