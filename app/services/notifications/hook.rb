# frozen_string_literal: true

require "digest"

module Notifications
  class SyntheticSource
    attr_reader :id

    def initialize(id)
      @id = id
    end
  end

  module Hook
    module_function

    def project_payload(project, extra = {})
      extra.stringify_keys.merge(
        "project_title" => project.title.to_s.truncate(30),
        "project_id" => project.id
      )
    end

    def task_payload(task, extra = {})
      project_payload(task.project, extra).merge(
        "task_title" => task.title.to_s.truncate(30),
        "task_id" => task.id
      )
    end

    def org_payload(organization, extra = {})
      extra.stringify_keys.merge("organization_name" => organization.name)
    end

    def emit(**kwargs)
      Emit.call(**kwargs)
    end

    def named_source(seed)
      uuid = ::Digest::UUID.uuid_v5("6ba7b810-9dad-11d1-80b4-00c04fd430c8", seed.to_s)
      SyntheticSource.new(uuid)
    end

    def organization_staff(organization)
      organization.organization_memberships.staff.includes(:user).map(&:user)
    end

    def organization_members(organization)
      organization.organization_memberships.active.includes(:user).map(&:user)
    end
  end
end
