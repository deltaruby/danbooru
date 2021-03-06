class PoolVersionsController < ApplicationController
  respond_to :html, :xml, :json
  before_filter :check_availabililty

  def index
    if params[:search] && params[:search][:pool_id].present?
      @pool = Pool.find(params[:search][:pool_id])
    end

    @pool_versions = PoolArchive.search(params[:search]).order("updated_at desc").paginate(params[:page], :limit => params[:limit], :search_count => params[:search])
    respond_with(@pool_versions) do |format|
      format.xml do
        render :xml => @pool_versions.to_xml(:root => "pool-versions")
      end
    end
  end

private

  def check_availabililty
    if !PoolArchive.enabled?
      respond_to do |format|
        format.html do
          flash[:notice] = "Archive service is not configured. Pool versions are not saved."
          redirect_to :back
        end
        format.json do
          render json: {success: false, reason: "Archive service is not configured"}.to_json, status: 501
        end
      end

      return false
    end
  end
end
