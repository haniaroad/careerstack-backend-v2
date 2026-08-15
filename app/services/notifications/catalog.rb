# frozen_string_literal: true

module Notifications
  module Catalog
    STAFF_INBOX = ENV.fetch("STAFF_INBOX", "hello@careerstack.co")
    APP_ORIGIN = ENV.fetch("APP_ORIGIN", "http://localhost:5173")

    CATEGORIES = {
      "account" => {
        label: "Security and account",
        description: "Invitations, removals, cancellations, receipts, and required account notices.",
        tier: "mandatory",
        can_disable: false,
        default_cadence: nil
      },
      "project_activity" => {
        label: "Project activity",
        description: "Assignments, submissions, applications, completions, and related project updates.",
        tier: "realtime_config",
        can_disable: true,
        default_cadence: "realtime"
      },
      "reminders" => {
        label: "Reminders and summaries",
        description: "Due dates, ending soon, review reminders, and weekly activity summaries.",
        tier: "digest_config",
        can_disable: true,
        default_cadence: "daily"
      }
    }.freeze

    COALESCABLE = %w[task_assigned task_approved submission_received].freeze

    EVENTS = {
      "organization_invitation" => { tier: "mandatory", category: "account", emit: true },
      "removed_from_project" => { tier: "mandatory", category: "account", emit: true },
      "project_cancelled" => { tier: "mandatory", category: "account", emit: true },
      "date_changed" => { tier: "mandatory", category: "account", emit: true },
      "corrections_requested" => { tier: "mandatory", category: "account", emit: true },
      "purchase_receipt" => { tier: "mandatory", category: "account", emit: true },
      "refund_confirmation" => { tier: "mandatory", category: "account", emit: true },
      "age_up_visibility_review" => { tier: "mandatory", category: "account", emit: true },
      "organization_offboarding" => { tier: "mandatory", category: "account", emit: true },
      "task_assigned" => { tier: "realtime_config", category: "project_activity", emit: true },
      "task_approved" => { tier: "realtime_config", category: "project_activity", emit: true },
      "submission_received" => { tier: "realtime_config", category: "project_activity", emit: true },
      "application_received" => { tier: "realtime_config", category: "project_activity", emit: true },
      "application_decision" => { tier: "realtime_config", category: "project_activity", emit: true },
      "application_overdue" => { tier: "realtime_config", category: "project_activity", emit: true },
      "project_invitation" => { tier: "realtime_config", category: "project_activity", emit: true },
      "participant_left" => { tier: "realtime_config", category: "project_activity", emit: true },
      "project_completed" => { tier: "realtime_config", category: "project_activity", emit: true },
      "grace_period_started" => { tier: "realtime_config", category: "project_activity", emit: true },
      "escalation_created" => { tier: "realtime_config", category: "project_activity", emit: true },
      "welcome" => { tier: "realtime_config", category: "project_activity", emit: true },
      "organization_ready" => { tier: "realtime_config", category: "project_activity", emit: true },
      "trial_credits_used_up" => { tier: "realtime_config", category: "project_activity", emit: true },
      "upgrade_request_received" => { tier: "realtime_config", category: "project_activity", emit: true },
      "not_enough_organization_credits" => { tier: "realtime_config", category: "project_activity", emit: true },
      "task_due_reminder" => { tier: "digest_config", category: "reminders", emit: true },
      "project_ending_soon" => { tier: "digest_config", category: "reminders", emit: true },
      "review_reminder" => { tier: "digest_config", category: "reminders", emit: true },
      "activity_summary" => { tier: "digest_config", category: "reminders", emit: true },
      "pending_invitation_reminder" => { tier: "digest_config", category: "reminders", emit: true },
      "account_security_change" => { tier: "mandatory", category: "account", emit: false },
      "suspension" => { tier: "mandatory", category: "account", emit: false },
      "policy_change" => { tier: "mandatory", category: "account", emit: false },
      "peer_review_received" => { tier: "realtime_config", category: "project_activity", emit: false },
      "peer_review_request" => { tier: "realtime_config", category: "project_activity", emit: false },
      "unread_project_messages" => { tier: "digest_config", category: "reminders", emit: false }
    }.freeze

    COPY = {
      "organization_invitation" => {
        title: "Organization invitation",
        heading: "You've been invited to CareerStack",
        body: "%{organization_name} invited you to join on CareerStack. Accepting takes about two minutes.",
        cta: "Accept invitation",
        path: "/invite/%{token}"
      },
      "removed_from_project" => {
        title: "Removed from project",
        heading: "You've been removed from a project",
        body: "You were removed from %{project_title}. Your record of approved work is unchanged.",
        cta: "Open My Work",
        path: "/my-work"
      },
      "project_cancelled" => {
        title: "Project cancelled",
        heading: "A project was cancelled",
        body: "%{project_title} was cancelled. Eligible join credits were restored.",
        cta: "Open My Work",
        path: "/my-work"
      },
      "date_changed" => {
        title: "Date changed",
        heading: "A project date changed",
        body: "The end date for %{project_title} was updated to %{ends_on}.",
        cta: "Open project",
        path: "/projects/%{project_id}"
      },
      "corrections_requested" => {
        title: "Changes requested",
        heading: "Changes were requested on a task",
        body: "Updates are needed on %{task_title} in %{project_title}. Review the feedback and resubmit.",
        cta: "Open task",
        path: "/tasks/%{task_id}"
      },
      "purchase_receipt" => {
        title: "Purchase receipt",
        heading: "Your credit purchase is confirmed",
        body: "Your personal credit pack purchase is complete.",
        cta: "Open Billing",
        path: "/billing"
      },
      "refund_confirmation" => {
        title: "Refund confirmation",
        heading: "A credit refund was processed",
        body: "Unused personal credits from a recent purchase were reversed.",
        cta: "Open Billing",
        path: "/billing"
      },
      "age_up_visibility_review" => {
        title: "Visibility review",
        heading: "Review your public profile visibility",
        body: "Your public identity stays private until you confirm it on your profile.",
        cta: "Review visibility",
        path: "/profile"
      },
      "organization_offboarding" => {
        title: "Organization offboarding",
        heading: "Organization access is changing",
        body: "%{organization_name} is in a read-only offboarding window with %{days_remaining} days remaining. Exports stay available.",
        cta: "Open organization",
        path: "/organization"
      },
      "task_assigned" => {
        title: "Task assigned",
        heading: "A task was assigned to you",
        body: "%{task_title} on %{project_title} is ready for you.",
        cta: "Open task",
        path: "/tasks/%{task_id}"
      },
      "task_approved" => {
        title: "Task approved",
        heading: "A task was approved",
        body: "%{task_title} on %{project_title} was approved.",
        cta: "Open task",
        path: "/tasks/%{task_id}"
      },
      "submission_received" => {
        title: "Submission received",
        heading: "A submission is ready to review",
        body: "A participant submitted %{task_title} on %{project_title}.",
        cta: "Open Inbox",
        path: "/inbox"
      },
      "application_received" => {
        title: "Application received",
        heading: "Someone applied to join",
        body: "A new application arrived for %{project_title}.",
        cta: "Open Inbox",
        path: "/inbox"
      },
      "application_decision" => {
        title: "Application decision",
        heading: "Your application was decided",
        body: "Your application to %{project_title} was %{decision_label}.",
        cta: "Open project",
        path: "/projects/%{project_id}"
      },
      "application_overdue" => {
        title: "Application overdue",
        heading: "An application is waiting",
        body: "A join application on %{project_title} has waited more than 72 hours.",
        cta: "Open Inbox",
        path: "/inbox"
      },
      "project_invitation" => {
        title: "Project invitation",
        heading: "You're invited to a project",
        body: "You were invited to join %{project_title}.",
        cta: "Open invitation",
        path: "/projects/%{project_id}"
      },
      "participant_left" => {
        title: "Participant left",
        heading: "A participant left the project",
        body: "A participant left %{project_title}.",
        cta: "Open project",
        path: "/projects/%{project_id}"
      },
      "project_completed" => {
        title: "Project completed",
        heading: "A project is complete",
        body: "%{project_title} is complete — all tasks were approved.",
        cta: "Open project",
        path: "/projects/%{project_id}"
      },
      "grace_period_started" => {
        title: "Grace period started",
        heading: "A project entered its grace period",
        body: "%{project_title} has passed its end date. Finish outstanding work before final expiration.",
        cta: "Open project",
        path: "/projects/%{project_id}"
      },
      "escalation_created" => {
        title: "Escalation created",
        heading: "A project needs attention",
        body: "%{project_title} needs attention (%{reason_label}).",
        cta: "Open Inbox",
        path: "/inbox"
      },
      "welcome" => {
        title: "Welcome",
        heading: "Welcome to CareerStack",
        body: "Your account is ready. Start from Home when you are.",
        cta: "Open Home",
        path: "/"
      },
      "organization_ready" => {
        title: "Organization is ready",
        heading: "Your organization is ready",
        body: "%{organization_name} is set up with trial credits to start a first project.",
        cta: "Open organization",
        path: "/organization"
      },
      "trial_credits_used_up" => {
        title: "Trial credits used up",
        heading: "Organization trial credits are used up",
        body: "%{organization_name} has no remaining pooled credits. New projects and memberships are blocked until more credits are granted.",
        cta: "Open Credits",
        path: "/organization?tab=credits"
      },
      "upgrade_request_received" => {
        title: "Upgrade request received",
        heading: "We received your upgrade request",
        body: "CareerStack staff will follow up about credits for %{organization_name}.",
        cta: "Open Credits",
        path: "/organization?tab=credits"
      },
      "not_enough_organization_credits" => {
        title: "Not enough organization credits",
        heading: "An action needs more credits",
        body: "A create, assign, or approve action on %{organization_name} was blocked because pooled credits are exhausted.",
        cta: "Open Credits",
        path: "/organization?tab=credits"
      },
      "task_due_reminder" => {
        title: "Task due reminder",
        heading: "A task is due soon",
        body: "%{task_title} on %{project_title} is due %{due_on}.",
        cta: "Open task",
        path: "/tasks/%{task_id}"
      },
      "project_ending_soon" => {
        title: "Project ending soon",
        heading: "A project is ending soon",
        body: "%{project_title} ends on %{ends_on}. Wrap up remaining work.",
        cta: "Open project",
        path: "/projects/%{project_id}"
      },
      "review_reminder" => {
        title: "Review reminder",
        heading: "A review is waiting",
        body: "Unreviewed work is waiting on %{project_title}.",
        cta: "Open Inbox",
        path: "/inbox"
      },
      "activity_summary" => {
        title: "Activity summary",
        heading: "Your CareerStack activity this week",
        body: "You had project activity this week. Open the app to catch up.",
        cta: "Open Home",
        path: "/"
      },
      "pending_invitation_reminder" => {
        title: "Pending invitation",
        heading: "An invitation is still open",
        body: "You have an unaccepted invitation waiting.",
        cta: "Open Home",
        path: "/"
      }
    }.freeze

    module_function

    def event!(event_key)
      EVENTS.fetch(event_key) { raise ArgumentError, "Unknown notification event #{event_key}" }
    end

    def copy_for(event_key)
      COPY.fetch(event_key) { raise ArgumentError, "Missing copy for #{event_key}" }
    end

    def interpolatable?(event_key)
      emit?(event_key)
    end

    def emit?(event_key)
      event!(event_key)[:emit]
    end

    def coalescable?(event_key)
      COALESCABLE.include?(event_key)
    end

    def interpolate(template, payload)
      template.to_s % payload.symbolize_keys
    rescue KeyError
      template.to_s
    end
  end
end
