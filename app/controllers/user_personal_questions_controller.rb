class UserPersonalQuestionsController < ApplicationController
  before_action :set_user_personal_question, only: %i[ show edit update destroy ]

  # GET /user_personal_questions or /user_personal_questions.json
  def index
    @user_personal_questions = UserPersonalQuestion.all
  end

  # GET /user_personal_questions/1 or /user_personal_questions/1.json
  def show
  end

  # GET /user_personal_questions/new
  def new
    @user_personal_question = UserPersonalQuestion.new
  end

  # GET /user_personal_questions/1/edit
  def edit
  end

  # POST /user_personal_questions or /user_personal_questions.json
  def create
    @user_personal_question = UserPersonalQuestion.new(user_personal_question_params)

    respond_to do |format|
      if @user_personal_question.save
        format.html { redirect_to @user_personal_question, notice: "User personal question was successfully created." }
        format.json { render :show, status: :created, location: @user_personal_question }
      else
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @user_personal_question.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /user_personal_questions/1 or /user_personal_questions/1.json
  def update
    respond_to do |format|
      if @user_personal_question.update(user_personal_question_params)
        format.html { redirect_to @user_personal_question, notice: "User personal question was successfully updated." }
        format.json { render :show, status: :ok, location: @user_personal_question }
      else
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @user_personal_question.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /user_personal_questions/1 or /user_personal_questions/1.json
  def destroy
    @user_personal_question.destroy
    respond_to do |format|
      format.html { redirect_to user_personal_questions_url, notice: "User personal question was successfully destroyed." }
      format.json { head :no_content }
    end
  end

  private
    # Use callbacks to share common setup or constraints between actions.
    def set_user_personal_question
      @user_personal_question = UserPersonalQuestion.find(params[:id])
    end

    # Only allow a list of trusted parameters through.
    def user_personal_question_params
      params.require(:user_personal_question).permit(:user_id, :personal_question_id, :answer)
    end
end
