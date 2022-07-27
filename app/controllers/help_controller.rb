class HelpController < ApplicationController
  respond_to :html, :json
  before_action :admin_only, only: [:new, :create, :edit,
                                    :update, :destroy]

  def show
    if params[:id] =~ /\A\d+\Z/
      @help = HelpPage.find(params[:id])
    else
      @help = HelpPage.find_by(name: HelpPage.normalize_name(params[:id]))
    end
    return redirect_to help_pages_path unless @help.present?
    @related = @help.related.split(', ')
    respond_with(@help)
  end

  def index
    @help_pages = HelpPage.help_index
    respond_with(@help_pages)
  end

  def new
    @help = HelpPage.new
    respond_with(@help)
  end

  def edit
    @help = HelpPage.find(params[:id])
    respond_with(@help)
  end

  def create
    @help = HelpPage.create(help_params)
    if @help.valid?
      flash[:notice] = 'Help page created'
    end
    respond_with(@help)
  end

  def update
    @help = HelpPage.find(params[:id])
    @help.update(help_params)
    if @help.valid?
      flash[:notice] = "Help entry updated"
    end
    respond_with(@help)
  end

  def destroy
    @help = HelpPage.find(params[:id])
    @help.destroy
    respond_with(@help)
  end

  private

  def help_params
  end
end
