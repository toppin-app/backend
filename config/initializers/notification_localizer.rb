class NotificationLocalizer
  def self.for(user:, type:, params: {})
    locale = case user.language
             when 0, '0', :es, 'es', 'ES' then :es
             when 1, '1', :en, 'en', 'EN' then :en
             else I18n.default_locale
             end

    I18n.with_locale(locale) do
      {
        title: I18n.t("notifications.#{type}.title", **params),
        body: I18n.t("notifications.#{type}.body", **params)
      }
    end
  end
end
