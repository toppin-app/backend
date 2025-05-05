class Purchase < ApplicationRecord
  belongs_to :user
  after_create :activate_product

  # Una vez la compra ha sido correctamente creada, activamos el producto.
  def activate_product

    case self.product_id 

        # BOOSTS
        when "boost_x1"
           self.user.increase_consumable("boosters",1)

        when "boost_x5"    
          self.user.increase_consumable("boosters",5)

        when "boost_x10"    
          self.user.increase_consumable("boosters",10)


        # SUPER LIKES
        when "superlike_x5"    
          self.user.increase_consumable("superlikes",5)

        when "superlike_x25"    
          self.user.increase_consumable("superlikes",25)

        when "superlike_x60"    
          self.user.increase_consumable("superlikes",60)


        # TOPPIN SWEET (TIRADAS RULETA)
        when "sweet_x5"    
          self.user.increase_consumable("roulette",5)

        when "sweet_10"    
          self.user.increase_consumable("roulette",10)

        when "sweet_x20"    
          self.user.increase_consumable("roulette",20)


        # PLANES PREMIUM
        when "toppin_premium_mensual"    
           self.user.update(current_subscription_name: "premium")
           self.user.update(current_subscription_id: "toppin_premium_mensual")

        when "toppin_premium_trimestral"    
           self.user.update(current_subscription_name: "premium")
           self.user.update(current_subscription_id: "toppin_premium_trimestral")

        when "toppin_premium_semestral"    
           self.user.update(current_subscription_name: "premium")
           self.user.update(current_subscription_id: "toppin_premium_semestral")


        # PLANES SUPREME
        when "toppin_supreme_mensual"    
           self.user.update(current_subscription_name: "supreme")
           self.user.update(current_subscription_id: "toppin_supreme_mensual")

        when "toppin_supreme_trimestral"    
           self.user.update(current_subscription_name: "supreme")
           self.user.update(current_subscription_id: "toppin_supreme_trimestral")

        when "toppin_supreme_semestral"    
           self.user.update(current_subscription_name: "supreme")
           self.user.update(current_subscription_id: "toppin_supreme_semestral")


    end


  end


end
