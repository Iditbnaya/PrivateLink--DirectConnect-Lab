# Contributing to Private Link Direct Connect Lab

Thank you for your interest in contributing to this project! This is an open-source infrastructure-as-code lab demonstrating Azure Private Link Service Direct Connect.

## How to Contribute

### Reporting Issues
- **Found a bug?** Check [existing issues](../../issues) first
- **Have a feature request?** Open an issue with the title `[FEATURE REQUEST]`
- **Include details**: Your Azure environment, PowerShell version, error messages (if applicable)

### Improving Documentation
- Typos, unclear explanations, or missing details? Feel free to:
  - Submit a pull request with corrections
  - Open an issue describing the problem
  - Suggest improvements to examples or deployment steps

### Improving Scripts
- Found a more efficient approach?
- Discovered a workaround for an issue?
- Want to add support for additional scenarios?

Please:
1. **Fork** the repository
2. **Create a feature branch**: `git checkout -b feature/your-improvement`
3. **Make your changes** with clear commit messages
4. **Test thoroughly** on your Azure subscription
5. **Submit a pull request** with description of changes

## Script Development Guidelines

### PowerShell Style
- Use proper error handling with `$ErrorActionPreference`
- Follow Azure CLI naming conventions
- Add helper functions for repeated operations
- Include color-coded output for clarity (Write-Host with -ForegroundColor)
- Document parameters with helpful comments

### Documentation
- Update README.md if adding new scenarios
- Update QUICK_REFERENCE.md with new commands
- Add comments explaining complex steps
- Include example outputs where applicable

### Testing
- Test deployments in your own Azure subscription
- Verify cleanup works properly
- Test both success and error paths
- Document any environment-specific requirements

## Code of Conduct

### Expected Behavior
- Be respectful and inclusive
- Welcome diverse perspectives
- Provide constructive feedback
- Focus on the code, not the person

### Unacceptable Behavior
- Harassment or discrimination
- Profanity or hostile language
- Sharing others' private information without consent

## Questions?

- 📖 **Documentation**: Start with README.md and QUICK_REFERENCE.md
- 🐛 **Issues**: Check [GitHub Issues](../../issues)
- 💬 **Discussion**: Use the [Discussions](../../discussions) section

---

**Thank you for making this project better!** 🙏
