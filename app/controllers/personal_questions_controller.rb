class PersonalQuestionsController < ApplicationController
  before_action :set_personal_question, only: %i[ show edit update destroy ]

  # GET /personal_questions or /personal_questions.json
  def index
    @personal_questions = PersonalQuestion.all
  end

  # GET /personal_questions/1 or /personal_questions/1.json
  def show
  end

  # GET /personal_questions/new
  def new
    @personal_question = PersonalQuestion.new
  end

  # GET /personal_questions/1/edit
  def edit
  end

  # POST /personal_questions or /personal_questions.json
  def create
    @personal_question = PersonalQuestion.new(personal_question_params)

    respond_to do |format|
      if @personal_question.save
        format.html { redirect_to @personal_question, notice: "Personal question was successfully created." }
        format.json { render :show, status: :created, location: @personal_question }
      else
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @personal_question.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /personal_questions/1 or /personal_questions/1.json
  def update
    respond_to do |format|
      if @personal_question.update(personal_question_params)
        format.html { redirect_to @personal_question, notice: "Personal question was successfully updated." }
        format.json { render :show, status: :ok, location: @personal_question }
      else
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @personal_question.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /personal_questions/1 or /personal_questions/1.json
  def destroy
    @personal_question.destroy
    respond_to do |format|
      format.html { redirect_to personal_questions_url, notice: "Personal question was successfully destroyed." }
      format.json { head :no_content }
    end
  end

  private
    # Use callbacks to share common setup or constraints between actions.
    def set_personal_question
      @personal_question = PersonalQuestion.find(params[:id])
    end

    # Only allow a list of trusted parameters through.
    def personal_question_params
      params.require(:personal_question).permit(:name)
    end
end
