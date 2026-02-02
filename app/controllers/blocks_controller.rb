class BlocksController < ApplicationController
  before_action :authenticate_user!
  before_action :check_admin

  # DELETE /blocks/1
  def destroy
    @block = Block.find(params[:id])
    user = @block.user
    
    @block.destroy
    
    redirect_to user_path(user), notice: 'Usuario desbloqueado correctamente.'
  end
end
