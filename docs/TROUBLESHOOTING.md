# Troubleshooting Package Installation

This guide helps you troubleshoot common package installation issues.

## Package Not Found Errors

If you see errors like:
```
ERROR: Package 'awscli' not found with the source(s) listed
ERROR: Package 'dotnetcore-sdk' not found
ERROR: Package 'nvm' not found
```

### Solution 1: Verify Package Names

The package names in `config/tools-config.json` must match the exact names in Chocolatey's repository.

#### How to Find Correct Package Names

1. **Search Chocolatey Website**:
   - Visit: https://community.chocolatey.org/packages
   - Search for the tool you want
   - Use the **exact package name** shown on the page

2. **Use Chocolatey Search**:
   ```powershell
   choco search <tool-name>
   ```

   Example:
   ```powershell
   choco search dotnet-sdk
   choco search awscli
   choco search nvm
   ```

3. **Check Package Info**:
   ```powershell
   choco info <package-name>
   ```

### Common Package Name Corrections

| Tool | ❌ Wrong Name | ✅ Correct Name | Notes |
|------|--------------|----------------|-------|
| NVM | `nvm` | `nvm.portable` | Use portable version for reliability |
| .NET SDK 3.1 | `dotnetcore-sdk` | `dotnet-sdk` | Modern package name |
| .NET SDK Latest | N/A | `dotnet-sdk` | Gets latest version |
| AWS CLI | `aws-cli` | `awscli` | No hyphen in name |
| Docker Desktop | `docker-desktop` | `docker-desktop` | ✅ Correct |
| 7-Zip | `7zip` | `7zip.install` | Use .install variant |

### Solution 2: Check Version Availability

Not all versions exist in Chocolatey. Some packages only have specific versions.

#### How to Check Available Versions

```powershell
choco info <package-name> --all-versions
```

Example:
```powershell
choco info dotnet-sdk --all-versions
choco info awscli --all-versions
```

#### Version Expression Tips

**Best Practice**: Use version families, not exact versions

| Expression | Meaning | Example Result |
|------------|---------|----------------|
| `~3.1.0` | Latest 3.1.x patch | Installs 3.1.426 |
| `~3.1.201` | Latest 3.1.x patch | Installs 3.1.426 |
| `^3.0.0` | Latest 3.x minor | Installs 3.22.1 |
| `latest` | Latest available | Installs newest |
| `3.1.201` | Exact version | Only if exists |

**Common Issue**: Requesting exact version that doesn't exist

❌ Wrong:
```json
"dotnetcore-sdk": {
  "version": "3.1.201",  // This exact version might not exist
  "packageName": "dotnet-sdk"
}
```

✅ Better:
```json
"dotnetcore-sdk": {
  "version": "~3.1",     // Gets latest 3.1.x
  "packageName": "dotnet-sdk"
}
```

✅ Best:
```json
"dotnetcore-sdk": {
  "version": "latest",   // Gets latest available
  "packageName": "dotnet-sdk"
}
```

### Solution 3: Update Configuration

Edit `config/tools-config.json` with correct package names:

```json
{
  "developmentTools": {
    "nvm": {
      "version": "~1.1.5",
      "packageName": "nvm.portable",  // ✅ Changed from "nvm"
      "source": "chocolatey"
    },
    "dotnetcore-sdk": {
      "version": "~3.1",              // ✅ Changed from "~3.1.201"
      "packageName": "dotnet-sdk",    // ✅ Changed from "dotnetcore-sdk"
      "source": "chocolatey"
    },
    "awscli": {
      "version": "latest",            // ✅ Changed from "~2.0.6"
      "packageName": "awscli",
      "source": "chocolatey"
    }
  }
}
```

## Other Common Issues

### Issue: Checksum Verification Failed

```
ERROR: Checksum verification failed for package 'nodejs'
```

**Cause**: Package integrity check failed (security feature)

**Solution**:
1. ✅ **DO NOT** disable checksum verification (security risk!)
2. ✅ Check your network connection
3. ✅ Check if you're behind a proxy that's intercepting HTTPS
4. ✅ Try again later (package might have been updated)
5. ✅ Report to package maintainer if it persists

### Issue: Exit Code 3010

```
ERROR: Failed to install dotnetcore-sdk (exit code: 3010)
```

**Cause**: This is actually a **SUCCESS** - means reboot required

**Solution**: The script now handles this correctly (v2.1+). If you see this message:
```
WARNING: dotnetcore-sdk installed successfully but REBOOT REQUIRED
```
Just reboot your machine after installation completes.

### Issue: Installation Hangs/Times Out

```
WARNING: Job for docker-desktop has exceeded 15 minute timeout
```

**Cause**: Large packages (like Docker) take a long time to install

**Solution**:
- Script now has 15-minute timeout protection (v2.1+)
- Large packages will show progress: `docker-desktop (8.3m)`
- If timeout occurs, package may still be installing in background
- Check with: `choco list --local-only`

### Issue: Permission Denied

```
ERROR: Access to the path 'C:\ProgramData\chocolatey' is denied
```

**Cause**: Not running as Administrator

**Solution**:
1. Close PowerShell
2. Right-click PowerShell → "Run as Administrator"
3. Run the script again

## Testing Package Installation Manually

Before updating the config, test packages manually:

```powershell
# Test if package exists
choco search <package-name> --exact

# Test installation (without committing)
choco install <package-name> --version <version> -y --whatif

# Actually install to test
choco install <package-name> --version <version> -y

# Uninstall test package
choco uninstall <package-name> -y
```

Example workflow:
```powershell
# 1. Find correct package name
choco search nvm
# Output: nvm.portable 1.1.12 [Approved]

# 2. Check available versions
choco info nvm.portable --all-versions
# Output shows: 1.1.12, 1.1.11, 1.1.10, etc.

# 3. Test installation
choco install nvm.portable --version 1.1 -y
# Uses version family - installs latest 1.1.x

# 4. Verify
nvm version

# 5. Update config with working values
# Edit config/tools-config.json:
"nvm": {
  "version": "~1.1",
  "packageName": "nvm.portable",
  "source": "chocolatey"
}
```

## Getting Help

1. **Check Chocolatey Package Page**: https://community.chocolatey.org/packages/<package-name>
2. **Check Package Issues**: Look for known issues on the package page
3. **Search Community**: https://community.chocolatey.org/
4. **Check Script Logs**: Review `logs/audit_*.log` for detailed error information
5. **Check Windows Event Log**: Look for "DevInstall" source in Application log

## Prevention

### Best Practices for Configuration

1. ✅ **Use version families** (`~3.1`) instead of exact versions (`3.1.201`)
2. ✅ **Use "latest"** when you don't need a specific version
3. ✅ **Test packages manually** before adding to config
4. ✅ **Use correct package names** from Chocolatey website
5. ✅ **Keep versions flexible** to get security patches automatically

### Example Good Configuration

```json
{
  "developmentTools": {
    "node": {
      "version": "~18",        // Gets latest 18.x
      "source": "nvm"
    },
    "dotnetcore-sdk": {
      "version": "~8.0",       // Gets latest 8.0.x
      "packageName": "dotnet-sdk",
      "source": "chocolatey"
    },
    "awscli": {
      "version": "latest",     // Always gets newest
      "packageName": "awscli",
      "source": "chocolatey"
    },
    "docker-desktop": {
      "version": "latest",     // Docker updates frequently
      "packageName": "docker-desktop",
      "source": "chocolatey"
    }
  }
}
```

## Updated Package Names (v2.1)

The following package names have been corrected in the default configuration:

| Tool | Old Name | New Name | Reason |
|------|----------|----------|--------|
| NVM | `nvm` | `nvm.portable` | More reliable portable version |
| .NET SDK | `dotnetcore-sdk` | `dotnet-sdk` | Modern package name |

If you're upgrading from an older version, update your `config/tools-config.json` with these corrected names.
