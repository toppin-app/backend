class NotificationLocalizer
  def self.for(user:, type:, params: {})
    I18n.with_locale(user.language.presence || I18n.default_locale) do
      {
        title: I18n.t("notifications.#{type}.title", **params),
        body: I18n.t("notifications.#{type}.body", **params)
      }
    end
  end
end
