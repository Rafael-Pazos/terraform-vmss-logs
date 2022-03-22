data "azurerm_subscription" "current" {}

resource "azurerm_monitor_action_group" "sub_admins" {
  name                = "sub_admins"
  resource_group_name = var.resource_group_name
  short_name          = "sub_admins"

  email_receiver {
    name          = "sendtoadmin"
    email_address = "rafael.pazos@microsoft.com"
    use_common_alert_schema = true
  }
  email_receiver {
    name                    = "sendtocontributor"
    email_address           = "rarod@contoso.com"
    use_common_alert_schema = true
  }
}

resource "azurerm_consumption_budget_subscription" "budget_1000" {
  name            = "rpr_eu_subs_1000"
  subscription_id = data.azurerm_subscription.current.subscription_id

  amount     = 1000
  time_grain = "Monthly"

  time_period {
    start_date = "2022-06-01T00:00:00Z"
    end_date   = "2024-07-01T00:00:00Z"
  }

  notification {
    enabled   = true
    threshold = 90.0
    operator  = "EqualTo"
    contact_groups = [
      azurerm_monitor_action_group.sub_admins.id,
    ]
    contact_roles = [
      "Owner",
    ]
  }
  notification {
    enabled        = false
    threshold      = 100.0
    operator       = "GreaterThan"
    threshold_type = "Forecasted" 
    contact_groups = [
      azurerm_monitor_action_group.sub_admins.id,
    ]
    contact_roles = [
      "Owner",
    ]
  }
}