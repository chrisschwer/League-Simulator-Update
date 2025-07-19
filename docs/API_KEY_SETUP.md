# API Key Setup Guide

## Overview
This guide explains how to securely store your RAPIDAPI_KEY locally so you don't need to set it manually each time.

## Storage Options

### 1. Project-Level .Renviron (Recommended)
Store the API key in your project directory. This key will only be available when working in this project.

**Setup:**
```bash
# Option A: Use the provided setup script
./setup_api_key.sh

# Option B: Create manually
echo "RAPIDAPI_KEY=your_api_key_here" >> .Renviron
```

**Pros:**
- Project-specific (won't affect other R projects)
- Already in .gitignore
- Easy to manage

### 2. User-Level .Renviron
Store the API key in your home directory. Available to all R sessions.

**Setup:**
```bash
# Find your home directory .Renviron
R -e "path.expand('~/.Renviron')"

# Add your key
echo "RAPIDAPI_KEY=your_api_key_here" >> ~/.Renviron
```

**Pros:**
- Available in all R projects
- Set once, use everywhere

**Cons:**
- Affects all R sessions
- Harder to manage multiple API keys

### 3. Shell Profile (Alternative)
Add to your shell configuration file.

**For zsh (default on macOS):**
```bash
echo 'export RAPIDAPI_KEY="your_api_key_here"' >> ~/.zshrc
source ~/.zshrc
```

**For bash:**
```bash
echo 'export RAPIDAPI_KEY="your_api_key_here"' >> ~/.bash_profile
source ~/.bash_profile
```

**Pros:**
- Available to all programs, not just R
- Works with command-line tools

**Cons:**
- Less secure (visible to all processes)
- Need to restart terminal

## Security Best Practices

### ✅ DO:
1. **Use .Renviron files** - R's standard for environment variables
2. **Keep .Renviron in .gitignore** - Never commit secrets
3. **Use restrictive permissions**:
   ```bash
   chmod 600 .Renviron  # Only you can read/write
   ```
4. **Rotate keys regularly** - Change them every few months
5. **Use different keys** for development and production

### ❌ DON'T:
1. **Hard-code keys in scripts** - Always use `Sys.getenv()`
2. **Share .Renviron files** - Each developer needs their own
3. **Commit to version control** - Even in private repos
4. **Use in Docker images** - Pass as runtime variables
5. **Log or print keys** - Be careful with debug output

## Verification

After setting up, verify your key is available:

```r
# In R console
Sys.getenv("RAPIDAPI_KEY")

# From command line
Rscript -e "cat('Key loaded:', nchar(Sys.getenv('RAPIDAPI_KEY')), 'chars\n')"

# Test API connection
Rscript test_api_connection.R
```

## Troubleshooting

### Key not loading?
1. **Restart R session** after creating .Renviron
2. **Check file location** - Must be in project root or home directory
3. **Check file format** - No spaces around `=` sign
4. **Manual load**: `readRenviron(".Renviron")`

### RStudio specific:
- Go to Session → Restart R
- Or use: `.rs.restartR()`

### Command line:
- New terminal sessions automatically load ~/.Renviron
- For current session: `source ~/.Renviron` won't work (use `readRenviron()` in R)

## Using with Docker

For production Docker deployments:

```dockerfile
# DON'T do this:
ENV RAPIDAPI_KEY=your_key  # Bad!

# DO this instead:
# Run container with:
docker run -e RAPIDAPI_KEY=$RAPIDAPI_KEY your_image
```

## GitHub Actions Integration

Your repo already has the key as a secret. Use it in workflows:

```yaml
- name: Run season transition
  env:
    RAPIDAPI_KEY: ${{ secrets.RAPIDAPI_KEY }}
  run: |
    Rscript scripts/season_transition.R 2024 2025
```

## Key Rotation

When you need to update your key:

1. **Get new key** from RapidAPI dashboard
2. **Update locally**:
   ```bash
   ./setup_api_key.sh  # Run setup again
   ```
3. **Update GitHub secret**:
   - Settings → Secrets → Update RAPIDAPI_KEY
4. **Test everything** still works

## Additional Security

For extra security, consider:

1. **Encrypted storage** using macOS Keychain:
   ```bash
   # Store in keychain
   security add-generic-password -a "$USER" -s "RAPIDAPI_KEY" -w "your_key"
   
   # Retrieve in R
   key <- system("security find-generic-password -a $USER -s RAPIDAPI_KEY -w", intern = TRUE)
   ```

2. **Key vault services** for production environments

Remember: Security is only as strong as your weakest link. Keep your keys safe!