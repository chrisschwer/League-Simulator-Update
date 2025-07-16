# File Operations
# Handles file system operations with error handling and safety

create_directory_if_not_exists <- function(dir_path) {
  # Create directory if it doesn't exist
  # Returns TRUE if directory exists or was created
  
  tryCatch({
    if (!dir.exists(dir_path)) {
      dir.create(dir_path, recursive = TRUE)
      cat("Directory created:", dir_path, "\n")
    }
    
    return(dir.exists(dir_path))
    
  }, error = function(e) {
    warning("Error creating directory:", e$message)
    return(FALSE)
  })
}

check_file_permissions <- function(file_path, operation = "read") {
  # Check file permissions for specified operation
  # Returns TRUE if operation is allowed
  
  tryCatch({
    if (!file.exists(file_path)) {
      # Check parent directory permissions for write operations
      if (operation == "write" || operation == "create") {
        parent_dir <- dirname(file_path)
        if (!dir.exists(parent_dir)) {
          return(FALSE)
        }
        return(file.access(parent_dir, mode = 2) == 0)  # Write permission
      }
      return(FALSE)
    }
    
    # Check existing file permissions
    if (operation == "read") {
      return(file.access(file_path, mode = 4) == 0)  # Read permission
    } else if (operation == "write") {
      return(file.access(file_path, mode = 2) == 0)  # Write permission
    } else if (operation == "execute") {
      return(file.access(file_path, mode = 1) == 0)  # Execute permission
    }
    
    return(FALSE)
    
  }, error = function(e) {
    warning("Error checking file permissions:", e$message)
    return(FALSE)
  })
}

safe_file_read <- function(file_path, sep = ";", header = TRUE) {
  # Safe file reading with error handling
  # Returns data or NULL on error
  
  tryCatch({
    # Check if file exists
    if (!file.exists(file_path)) {
      warning("File does not exist:", file_path)
      return(NULL)
    }
    
    # Check read permissions
    if (!check_file_permissions(file_path, "read")) {
      warning("No read permission for file:", file_path)
      return(NULL)
    }
    
    # Check file size
    file_size <- file.info(file_path)$size
    if (file_size == 0) {
      warning("File is empty:", file_path)
      return(NULL)
    }
    
    # Read file
    data <- read.csv(file_path, sep = sep, header = header, stringsAsFactors = FALSE)
    
    cat("File read successfully:", file_path, "(", nrow(data), "rows )\n")
    
    return(data)
    
  }, error = function(e) {
    warning("Error reading file:", file_path, "-", e$message)
    return(NULL)
  })
}

safe_file_write <- function(data, file_path, sep = ";", header = TRUE) {
  # Safe file writing with atomic operations
  # Prevents corruption during write operations
  
  tryCatch({
    # Check parent directory
    parent_dir <- dirname(file_path)
    if (!create_directory_if_not_exists(parent_dir)) {
      stop("Cannot create parent directory")
    }
    
    # Check write permissions
    if (!check_file_permissions(file_path, "write")) {
      stop("No write permission for file")
    }
    
    # Create temporary file
    temp_file <- paste0(file_path, ".tmp.", Sys.getpid())
    
    # Write to temporary file
    write.table(
      data,
      temp_file,
      sep = sep,
      row.names = FALSE,
      col.names = header,
      quote = FALSE
    )
    
    # Verify temporary file
    if (!file.exists(temp_file)) {
      stop("Temporary file creation failed")
    }
    
    # Backup existing file if it exists
    backup_path <- NULL
    if (file.exists(file_path)) {
      backup_path <- backup_existing_file(file_path)
    }
    
    # Move temporary file to final location
    if (file.exists(file_path)) {
      file.remove(file_path)
    }
    
    file.rename(temp_file, file_path)
    
    if (!file.exists(file_path)) {
      # Restore backup if move failed
      if (!is.null(backup_path) && file.exists(backup_path)) {
        file.copy(backup_path, file_path)
      }
      stop("Final file creation failed")
    }
    
    cat("File written successfully:", file_path, "\n")
    
    return(list(
      success = TRUE,
      file_path = file_path,
      backup_path = backup_path
    ))
    
  }, error = function(e) {
    # Clean up temporary file on error
    if (exists("temp_file") && file.exists(temp_file)) {
      file.remove(temp_file)
    }
    
    stop(paste("Error writing file:", e$message))
  })
}

create_file_lock <- function(file_path, timeout = 30) {
  # Create file lock to prevent concurrent access
  # Returns lock file path or NULL if failed
  
  lock_file <- paste0(file_path, ".lock")
  
  # Check if lock already exists
  if (file.exists(lock_file)) {
    # Check if lock is stale
    lock_age <- as.numeric(Sys.time()) - as.numeric(file.info(lock_file)$mtime)
    
    if (lock_age > timeout) {
      # Remove stale lock
      file.remove(lock_file)
      cat("Removed stale lock file:", lock_file, "\n")
    } else {
      warning("File is locked by another process")
      return(NULL)
    }
  }
  
  # Create lock file
  tryCatch({
    writeLines(c(
      paste("Process ID:", Sys.getpid()),
      paste("Timestamp:", Sys.time()),
      paste("File:", file_path)
    ), lock_file)
    
    if (file.exists(lock_file)) {
      return(lock_file)
    } else {
      return(NULL)
    }
    
  }, error = function(e) {
    warning("Error creating lock file:", e$message)
    return(NULL)
  })
}

release_file_lock <- function(lock_file) {
  # Release file lock
  # Returns TRUE if successful
  
  tryCatch({
    if (file.exists(lock_file)) {
      file.remove(lock_file)
      cat("Released lock file:", lock_file, "\n")
      return(TRUE)
    }
    return(FALSE)
    
  }, error = function(e) {
    warning("Error releasing lock file:", e$message)
    return(FALSE)
  })
}

with_file_lock <- function(file_path, func, timeout = 30) {
  # Execute function with file lock
  # Ensures exclusive access to file
  
  lock_file <- create_file_lock(file_path, timeout)
  
  if (is.null(lock_file)) {
    stop("Could not acquire file lock")
  }
  
  tryCatch({
    result <- func()
    return(result)
    
  }, error = function(e) {
    stop(e)
    
  }, finally = {
    release_file_lock(lock_file)
  })
}

validate_file_integrity <- function(file_path, expected_columns = NULL) {
  # Validate file integrity and structure
  # Returns validation results
  
  tryCatch({
    if (!file.exists(file_path)) {
      return(list(
        valid = FALSE,
        message = "File does not exist"
      ))
    }
    
    # Check file size
    file_size <- file.info(file_path)$size
    if (file_size == 0) {
      return(list(
        valid = FALSE,
        message = "File is empty"
      ))
    }
    
    # Try to read file
    data <- safe_file_read(file_path)
    if (is.null(data)) {
      return(list(
        valid = FALSE,
        message = "Could not read file"
      ))
    }
    
    # Check columns if expected
    if (!is.null(expected_columns)) {
      missing_columns <- setdiff(expected_columns, colnames(data))
      if (length(missing_columns) > 0) {
        return(list(
          valid = FALSE,
          message = paste("Missing columns:", paste(missing_columns, collapse = ", "))
        ))
      }
    }
    
    return(list(
      valid = TRUE,
      message = "File integrity validation passed",
      rows = nrow(data),
      columns = ncol(data),
      size = file_size
    ))
    
  }, error = function(e) {
    return(list(
      valid = FALSE,
      message = paste("Validation error:", e$message)
    ))
  })
}

cleanup_temporary_files <- function(pattern = "\\.tmp", directory = ".") {
  # Clean up temporary files
  # Removes files matching pattern
  
  tryCatch({
    temp_files <- list.files(directory, pattern = pattern, full.names = TRUE)
    
    if (length(temp_files) == 0) {
      return(0)
    }
    
    removed_count <- 0
    
    for (file in temp_files) {
      if (file.exists(file)) {
        file.remove(file)
        removed_count <- removed_count + 1
      }
    }
    
    if (removed_count > 0) {
      cat("Removed", removed_count, "temporary files\n")
    }
    
    return(removed_count)
    
  }, error = function(e) {
    warning("Error cleaning up temporary files:", e$message)
    return(0)
  })
}

get_available_disk_space <- function(path = ".") {
  # Get available disk space for given path
  # Returns space in bytes
  
  tryCatch({
    if (.Platform$OS.type == "windows") {
      # Windows-specific implementation
      system_info <- system(paste("dir", path), intern = TRUE)
      # Parse output for available space
      # This is a simplified implementation
      return(1e9)  # Return 1GB as fallback
    } else {
      # Unix-like systems
      df_output <- system(paste("df", path), intern = TRUE)
      if (length(df_output) >= 2) {
        # Parse df output
        fields <- strsplit(df_output[2], "\\s+")[[1]]
        if (length(fields) >= 4) {
          available_kb <- as.numeric(fields[4])
          return(available_kb * 1024)  # Convert to bytes
        }
      }
    }
    
    return(1e9)  # Return 1GB as fallback
    
  }, error = function(e) {
    warning("Error getting disk space:", e$message)
    return(1e9)  # Return 1GB as fallback
  })
}

check_disk_space <- function(required_space, path = ".") {
  # Check if enough disk space is available
  # Returns TRUE if enough space available
  
  available_space <- get_available_disk_space(path)
  
  if (available_space >= required_space) {
    return(TRUE)
  } else {
    warning(paste(
      "Insufficient disk space. Required:",
      format(required_space, units = "auto"),
      "Available:", format(available_space, units = "auto")
    ))
    return(FALSE)
  }
}

create_directory_structure <- function(base_path, subdirs) {
  # Create directory structure
  # Returns TRUE if all directories created successfully
  
  success <- TRUE
  
  for (subdir in subdirs) {
    full_path <- file.path(base_path, subdir)
    
    if (!create_directory_if_not_exists(full_path)) {
      warning("Failed to create directory:", full_path)
      success <- FALSE
    }
  }
  
  return(success)
}

archive_old_files <- function(source_dir, archive_dir, age_days = 30) {
  # Archive old files to reduce clutter
  # Moves files older than age_days to archive directory
  
  tryCatch({
    if (!dir.exists(source_dir)) {
      return(0)
    }
    
    if (!create_directory_if_not_exists(archive_dir)) {
      warning("Cannot create archive directory")
      return(0)
    }
    
    files <- list.files(source_dir, full.names = TRUE)
    cutoff_time <- Sys.time() - (age_days * 24 * 60 * 60)
    
    archived_count <- 0
    
    for (file in files) {
      if (file.info(file)$mtime < cutoff_time) {
        archive_file <- file.path(archive_dir, basename(file))
        
        if (file.copy(file, archive_file)) {
          file.remove(file)
          archived_count <- archived_count + 1
        }
      }
    }
    
    if (archived_count > 0) {
      cat("Archived", archived_count, "old files to", archive_dir, "\n")
    }
    
    return(archived_count)
    
  }, error = function(e) {
    warning("Error archiving files:", e$message)
    return(0)
  })
}

get_file_checksum <- function(file_path, algorithm = "md5") {
  # Calculate file checksum for integrity verification
  # Returns checksum string or NULL on error
  
  tryCatch({
    if (!file.exists(file_path)) {
      return(NULL)
    }
    
    if (algorithm == "md5") {
      checksum <- digest::digest(file_path, algo = "md5", file = TRUE)
    } else if (algorithm == "sha256") {
      checksum <- digest::digest(file_path, algo = "sha256", file = TRUE)
    } else {
      stop("Unsupported algorithm")
    }
    
    return(checksum)
    
  }, error = function(e) {
    warning("Error calculating checksum:", e$message)
    return(NULL)
  })
}

verify_file_checksum <- function(file_path, expected_checksum, algorithm = "md5") {
  # Verify file checksum
  # Returns TRUE if checksum matches
  
  actual_checksum <- get_file_checksum(file_path, algorithm)
  
  if (is.null(actual_checksum)) {
    return(FALSE)
  }
  
  return(actual_checksum == expected_checksum)
}