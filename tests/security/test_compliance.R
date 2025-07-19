# Compliance Testing
# Ensures application meets regulatory and compliance requirements

library(testthat)
library(jsonlite)

context("Compliance and regulatory requirements")

test_that("Data privacy compliance (GDPR)", {
  skip_if_not(Sys.getenv("TEST_COMPLIANCE_GDPR", "FALSE") == "TRUE",
              "GDPR compliance testing disabled")
  
  base_url <- test_infrastructure_exports$config$production_url
  
  # Test data subject rights
  
  # 1. Right to access (data portability)
  access_response <- GET(
    paste0(base_url, "/api/user/data/export"),
    add_headers(Authorization = "Bearer test-user-token")
  )
  
  if (status_code(access_response) == 200) {
    exported_data <- content(access_response, as = "parsed")
    
    # Data should be in portable format
    expect_true("format" %in% names(exported_data),
                info = "Export should specify format")
    
    expect_true(exported_data$format %in% c("json", "csv"),
                info = "Export format should be portable")
  }
  
  # 2. Right to erasure (right to be forgotten)
  deletion_response <- DELETE(
    paste0(base_url, "/api/user/data"),
    add_headers(Authorization = "Bearer test-user-token")
  )
  
  if (status_code(deletion_response) %in% c(200, 204)) {
    # Verify data is actually deleted
    verify_response <- GET(
      paste0(base_url, "/api/user/data"),
      add_headers(Authorization = "Bearer test-user-token")
    )
    
    expect_equal(status_code(verify_response), 404,
                 info = "User data should be deleted")
  }
  
  # 3. Privacy policy endpoint
  privacy_response <- GET(paste0(base_url, "/privacy-policy"))
  
  expect_equal(status_code(privacy_response), 200,
               info = "Privacy policy should be accessible")
  
  if (status_code(privacy_response) == 200) {
    policy_content <- content(privacy_response, as = "text")
    
    # Check for required GDPR elements
    gdpr_requirements <- c(
      "data controller",
      "lawful basis",
      "data retention",
      "third party",
      "your rights",
      "contact"
    )
    
    for (requirement in gdpr_requirements) {
      expect_true(grepl(requirement, policy_content, ignore.case = TRUE),
                  info = sprintf("Privacy policy should mention '%s'", requirement))
    }
  }
  
  # 4. Consent management
  consent_response <- GET(
    paste0(base_url, "/api/user/consent"),
    add_headers(Authorization = "Bearer test-user-token")
  )
  
  if (status_code(consent_response) == 200) {
    consent_data <- content(consent_response, as = "parsed")
    
    expect_true("consents" %in% names(consent_data),
                info = "Should provide consent information")
    
    # Should track consent timestamp
    if ("consents" %in% names(consent_data) && length(consent_data$consents) > 0) {
      for (consent in consent_data$consents) {
        expect_true("timestamp" %in% names(consent),
                    info = "Consent should have timestamp")
        expect_true("purpose" %in% names(consent),
                    info = "Consent should specify purpose")
      }
    }
  }
})

test_that("Audit logging meets compliance requirements", {
  skip_if_not(Sys.getenv("TEST_AUDIT_LOGGING", "FALSE") == "TRUE",
              "Audit logging testing disabled")
  
  # Define events that must be logged for compliance
  required_audit_events <- list(
    authentication = c("login", "logout", "failed_login"),
    authorization = c("access_granted", "access_denied"),
    data_access = c("data_viewed", "data_exported", "data_modified"),
    admin_actions = c("config_changed", "user_modified", "permission_changed")
  )
  
  # Check if audit log endpoint exists and is protected
  audit_response <- GET(
    paste0(test_infrastructure_exports$config$production_url, "/api/admin/audit-logs"),
    add_headers(Authorization = "Bearer admin-token")
  )
  
  # Audit logs should be protected
  if (is.null(headers(audit_response)$authorization)) {
    expect_true(status_code(audit_response) %in% c(401, 403),
                info = "Audit logs should require authentication")
  }
  
  # If we have access, verify log structure
  if (status_code(audit_response) == 200) {
    audit_logs <- content(audit_response, as = "parsed")
    
    if ("logs" %in% names(audit_logs) && length(audit_logs$logs) > 0) {
      sample_log <- audit_logs$logs[[1]]
      
      # Required fields for compliance
      required_fields <- c(
        "timestamp",
        "user_id",
        "action",
        "resource",
        "result",
        "ip_address"
      )
      
      for (field in required_fields) {
        expect_true(field %in% names(sample_log),
                    info = sprintf("Audit log should contain '%s'", field))
      }
      
      # Timestamp should be in ISO format
      if ("timestamp" %in% names(sample_log)) {
        expect_true(grepl("^\\d{4}-\\d{2}-\\d{2}T", sample_log$timestamp),
                    info = "Timestamp should be in ISO format")
      }
    }
  }
  
  # Test audit log retention
  retention_response <- GET(
    paste0(test_infrastructure_exports$config$production_url, "/api/admin/audit-retention")
  )
  
  if (status_code(retention_response) == 200) {
    retention_policy <- content(retention_response, as = "parsed")
    
    expect_true("retention_days" %in% names(retention_policy),
                info = "Should specify audit log retention period")
    
    if ("retention_days" %in% names(retention_policy)) {
      # Many regulations require 90+ days
      expect_gte(retention_policy$retention_days, 90,
                 info = "Audit logs should be retained for at least 90 days")
    }
  }
})

test_that("Data encryption meets standards", {
  skip_if_not(Sys.getenv("TEST_ENCRYPTION", "FALSE") == "TRUE",
              "Encryption testing disabled")
  
  # Test encryption at rest
  if (Sys.which("kubectl") != "") {
    # Check PVC encryption
    pvc_check <- system2(
      "kubectl",
      args = c("get", "pvc", "-l", "app=league-simulator", "-n", "production", "-o", "json"),
      stdout = TRUE,
      stderr = TRUE
    )
    
    if (attr(pvc_check, "status") == 0) {
      pvc_data <- fromJSON(paste(pvc_check, collapse = "\n"))
      
      if ("items" %in% names(pvc_data) && length(pvc_data$items) > 0) {
        for (pvc in pvc_data$items) {
          # Check for encryption annotation or storage class
          annotations <- pvc$metadata$annotations
          storage_class <- pvc$spec$storageClassName
          
          encrypted <- FALSE
          
          # Check annotations for encryption
          if (!is.null(annotations)) {
            if ("encryption" %in% names(annotations)) {
              encrypted <- annotations$encryption == "enabled"
            }
          }
          
          # Check storage class (provider-specific)
          if (!is.null(storage_class)) {
            encrypted <- encrypted || grepl("encrypted", storage_class, ignore.case = TRUE)
          }
          
          expect_true(encrypted,
                      info = sprintf("PVC %s should use encrypted storage", 
                                   pvc$metadata$name))
        }
      }
    }
  }
  
  # Test sensitive data handling
  sensitive_fields <- c("password", "api_key", "secret", "token", "ssn", "credit_card")
  
  # Check database schema (if accessible)
  schema_response <- GET(
    paste0(test_infrastructure_exports$config$production_url, "/api/admin/schema"),
    add_headers(Authorization = "Bearer admin-token")
  )
  
  if (status_code(schema_response) == 200) {
    schema_data <- content(schema_response, as = "parsed")
    
    if ("tables" %in% names(schema_data)) {
      for (table in schema_data$tables) {
        if ("columns" %in% names(table)) {
          for (column in table$columns) {
            # Check if sensitive fields are encrypted
            if (tolower(column$name) %in% sensitive_fields) {
              expect_true("encrypted" %in% names(column) && column$encrypted,
                          info = sprintf("Column %s.%s should be encrypted",
                                       table$name, column$name))
            }
          }
        }
      }
    }
  }
})

test_that("Access control follows principle of least privilege", {
  skip_if_not(Sys.getenv("TEST_ACCESS_CONTROL", "FALSE") == "TRUE",
              "Access control testing disabled")
  
  base_url <- test_infrastructure_exports$config$production_url
  
  # Define role-based access matrix
  access_matrix <- list(
    anonymous = list(
      allowed = c("/", "/health", "/api/status"),
      forbidden = c("/api/admin", "/api/user", "/api/internal")
    ),
    user = list(
      allowed = c("/api/user/profile", "/api/simulate"),
      forbidden = c("/api/admin", "/api/internal")
    ),
    admin = list(
      allowed = c("/api/admin/users", "/api/admin/config"),
      forbidden = c()  # Admins can access everything
    )
  )
  
  # Test each role
  for (role in names(access_matrix)) {
    role_config <- access_matrix[[role]]
    
    # Set up authentication header based on role
    auth_header <- switch(role,
      anonymous = list(),
      user = list(Authorization = "Bearer user-token"),
      admin = list(Authorization = "Bearer admin-token")
    )
    
    # Test allowed endpoints
    for (endpoint in role_config$allowed) {
      response <- do.call(GET, c(
        list(url = paste0(base_url, endpoint)),
        if (length(auth_header) > 0) list(config = add_headers(.headers = auth_header)) else list()
      ))
      
      expect_true(status_code(response) %in% c(200, 204),
                  info = sprintf("Role '%s' should access %s", role, endpoint))
    }
    
    # Test forbidden endpoints
    for (endpoint in role_config$forbidden) {
      response <- do.call(GET, c(
        list(url = paste0(base_url, endpoint)),
        if (length(auth_header) > 0) list(config = add_headers(.headers = auth_header)) else list()
      ))
      
      expect_true(status_code(response) %in% c(401, 403),
                  info = sprintf("Role '%s' should not access %s", role, endpoint))
    }
  }
})

test_that("Security update process is documented", {
  skip_if_not(file.exists("SECURITY.md") || file.exists("docs/SECURITY.md"),
              "Security documentation not found")
  
  # Find security documentation
  security_file <- if (file.exists("SECURITY.md")) "SECURITY.md" else "docs/SECURITY.md"
  
  security_content <- readLines(security_file)
  security_text <- paste(security_content, collapse = "\n")
  
  # Check for required sections
  required_sections <- list(
    vulnerability_reporting = c("report", "vulnerability", "security issue"),
    update_process = c("security update", "patch", "hotfix"),
    disclosure_policy = c("disclosure", "responsible", "coordinate"),
    contact_info = c("contact", "email", "security team")
  )
  
  for (section_name in names(required_sections)) {
    keywords <- required_sections[[section_name]]
    
    section_found <- FALSE
    for (keyword in keywords) {
      if (grepl(keyword, security_text, ignore.case = TRUE)) {
        section_found <- TRUE
        break
      }
    }
    
    expect_true(section_found,
                info = sprintf("Security documentation should cover '%s'", 
                             gsub("_", " ", section_name)))
  }
  
  # Check for security contact email
  email_pattern <- "[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}"
  expect_true(grepl(email_pattern, security_text),
              info = "Security documentation should include contact email")
})

test_that("Compliance dashboard provides necessary metrics", {
  skip_if_not(Sys.getenv("TEST_COMPLIANCE_DASHBOARD", "FALSE") == "TRUE",
              "Compliance dashboard testing disabled")
  
  dashboard_response <- GET(
    paste0(test_infrastructure_exports$config$production_url, "/api/admin/compliance"),
    add_headers(Authorization = "Bearer admin-token")
  )
  
  if (status_code(dashboard_response) == 200) {
    compliance_data <- content(dashboard_response, as = "parsed")
    
    # Required compliance metrics
    required_metrics <- c(
      "last_security_scan",
      "vulnerabilities_count",
      "patch_compliance_percentage",
      "audit_coverage",
      "encryption_status",
      "access_reviews_pending",
      "data_retention_compliance"
    )
    
    for (metric in required_metrics) {
      expect_true(metric %in% names(compliance_data),
                  info = sprintf("Compliance dashboard should show '%s'", metric))
    }
    
    # Check metric values for concerning issues
    if ("vulnerabilities_count" %in% names(compliance_data)) {
      if ("high" %in% names(compliance_data$vulnerabilities_count)) {
        expect_equal(compliance_data$vulnerabilities_count$high, 0,
                     info = "Should have no high severity vulnerabilities")
      }
    }
    
    if ("patch_compliance_percentage" %in% names(compliance_data)) {
      expect_gte(compliance_data$patch_compliance_percentage, 95,
                 info = "Patch compliance should be at least 95%")
    }
  }
})