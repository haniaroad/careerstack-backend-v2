# frozen_string_literal: true

module Api
  module V1
    class ProgramsController < BaseController
      def index
        access = Organizations::Access.staff!(user: current_user, organization_id: params[:organization_id])
        programs = access.organization.programs.order(:name)
        render json: { programs: programs.map { |program| ProgramSerializer.call(program) } }
      end

      def create
        access = Organizations::Access.staff!(user: current_user, organization_id: params[:organization_id])
        program = Programs::Create.call(actor: current_user, organization: access.organization, params: program_params)
        render json: { program: ProgramSerializer.call(program) }, status: :created
      end

      def update
        program = find_program!
        Organizations::Access.staff!(user: current_user, organization_id: program.organization_id)
        updated = Programs::Update.call(actor: current_user, program: program, params: program_params)
        render json: { program: ProgramSerializer.call(updated) }
      end

      def destroy
        program = find_program!
        Organizations::Access.admin!(user: current_user, organization_id: program.organization_id)
        Programs::DeleteEmptyDraft.call(program: program)
        head :no_content
      end

      def archive
        program = find_program!
        Organizations::Access.admin!(user: current_user, organization_id: program.organization_id)
        archived = Programs::Archive.call(program: program)
        render json: { program: ProgramSerializer.call(archived) }
      end

      private

      def find_program!
        Program.find(params[:id])
      end

      def program_params
        params.permit(:name, :description, :status)
      end
    end
  end
end
