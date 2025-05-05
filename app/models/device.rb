class Device < ApplicationRecord
    validates :device_uid, :token, :so, :presence => true
    belongs_to :user

    def self.register(token, so, device_uid, user)
      d = Device.where(device_uid: device_uid)
      if (d.any?) # existe, comprobamos y modificamos si procede
          d = d.last

          # Si el device existe, pero está asociado a otro usuario
            if (d.user_id != user.id) 
                d.token = token
                d.so = so
                d.user_id = user.id
                d.save
                d
            end

            # Si el device existe, pero tiene otro token
          if (d.token != token)
                d.token = token
                d.so = so
                d.save
              d
            else
                d
          end

        # El device no existe, lo damos de alta
      else 
        # creamos el propio dispositivo
          new_device = Device.create(:token => token, :so => so, :device_uid => device_uid, :user => user)
          # Lo añadimos al usuario correspondiente
          new_device
      end

  end


  # Mandar push individual a un usuario en concreto
  def self.sendIndividualPush(user_id, title, message, action = nil, image = nil, permission = nil)


    user = User.find(user_id)

    # Si no ha dado permiso de push, no mandamos
    if !user.push_general
      return
    end

    # Si por parámetro nos envían un tipo de permiso en concreto, lo comprobamos
    if !permission.nil?

      if !user[permission]
        return
      end

    end


    # Extraemos todos los dispositivos de un usuario
    devices = Device.where(user_id: user_id)

    # Si no hay devices, salimos
    if !devices.any?
      return
    end


    # Preparamos un par de arrays para diferenciar los token
    android_tokens = []

    # Recorremos los devices, llamando a los métodos de push android o ios
    devices.each do |device|
        if device.so == "ios"
            self.sendIOSPush(title, message, device.token, nil, nil, action)
        else
            android_tokens << device.token
        end
    end
    
    # Preparamos las notis de android
    if android_tokens.any?
        self.sendAndroidPush(title, message, android_tokens, image, nil, nil, action)
    end
    
    # Una vez creadas las notificaciones, mandamos las push.
    Rpush.push
  end


  def self.sendIOSPush(title, message, token, image = nil, goto = nil, goto_type = nil, action = nil)

        n = Rpush::Gcm::Notification.new
        n.app = Rpush::Gcm::App.last
        n.registration_ids = [token]
        n.priority = 'high'
        n.content_available = true

        n.notification = { body: message, title: title, sound: 'Sms.mp3' }

        n.data = { goto: goto, goto_type: goto_type, action: action, message: message }
        
        n.save!
        

    end

    def self.sendAndroidPush(title, message, android_token, image = nil, goto = nil, goto_type = nil, action = nil)

        n = Rpush::Gcm::Notification.new
        n.app = Rpush::Gcm::App.first
        n.registration_ids = android_token
        n.priority = 'high'
        n.content_available = true

        n.notification = { body: message, title: title, sound: 'sms.mp3' }

        n.data = { goto: goto, goto_type: goto_type, action: action, message: message }

        n.save!

    end

  # Push a todos los devices
  def self.sendPushAll(title, message, image = nil, goto = nil, goto_type = nil)

        all_devices = Device.all

        number_of_devices = all_devices.count.to_f

        number_of_blocks_arrray = (number_of_devices/999).ceil

        array_of_devices = all_devices.in_groups(number_of_blocks_arrray,false)

        array_of_devices.each do | devices |

        android_tokens = []
        ios_tokens = []
        
        devices.each do |device|
            if device.so == "ios"
                ios_tokens << device.token
            else
                android_tokens << device.token
            end
        end

      if android_tokens.count > 0 
        

            self.sendAndroidPush(title, message, android_tokens, image, goto, goto_type)


      end


        ios_tokens.each do |token|

          self.sendIOSPush(title, message, token, image, goto, goto_type)

        end

    
           p "Tanda de push enviada"
           Rpush.push

        end


  end
end