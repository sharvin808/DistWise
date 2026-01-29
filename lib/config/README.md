# API Keys Configuration

This directory contains sensitive API keys and configuration files.

## Setup Instructions

1. **Copy the example file:**
   ```bash
   cp api_keys.example.dart api_keys.dart
   ```

2. **Edit `api_keys.dart`** and replace the placeholder values with your actual API keys.

3. **Never commit `api_keys.dart`** - This file is already in `.gitignore` to prevent accidental commits.

## Files

- `api_keys.example.dart` - Template file with placeholder values (safe to commit)
- `api_keys.dart` - Your actual API keys (DO NOT COMMIT - ignored by git)

## Security Best Practices

✅ **DO:**
- Keep your API keys in `api_keys.dart`
- Use environment variables for production deployments
- Rotate keys regularly
- Use different keys for development and production

❌ **DON'T:**
- Commit actual API keys to version control
- Share your `api_keys.dart` file
- Hardcode API keys directly in your source code
- Use production API keys in development

## Current API Services

The app currently uses these services:

- **OpenStreetMap Tiles**: Free, no API key required
- **OSRM Routing**: Free public service, no API key required
- **Geocoding**: Using the `geocoding` package with free services

If you upgrade to paid services or add new APIs, update the `api_keys.dart` file accordingly.
