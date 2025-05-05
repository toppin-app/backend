module ApplicationHelper

	# Helper que nos devuelve un icono de check o cruces si un valor es true o false
	def true_false(value)
	  if value==true
	    "<i class='fa fa-check text-success'></i>".html_safe
	   else
	    "<i class='fa fa-times text-danger'></i>".html_safe
	   end
	end    



	def weekday(weekdays)

		weekdays = weekdays.split(",")

		names = ["","Lunes", "Martes", "Miércoles", "Jueves", "Viernes", "Sábado","Domingo"]

		result = ""

		weekdays.each do |w|


	    	result = result + names[w.to_i] + ","

	    end

	    return result.chop
	end

	
end
