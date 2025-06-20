# Security Policy

**Proxmox Enhanced Configuration Utility (PECU)**  
Repository: `Danilop95/Proxmox-Enhanced-Configuration-Utility`  
License: GPL-3.0  
Primary maintainer: [@Danilop95](https://github.com/Danilop95)  

---

## 1. Scope

This security policy applies to all first-party content in this repository:

| Component            | Description                                           | Language | Support Status |
|----------------------|-------------------------------------------------------|----------|----------------|
| `src/`               | Main script `proxmox-configurator.sh`                 | Bash     | Supported      |
| `scripts/`           | Release selector and helper utilities                 | Bash     | Supported      |
| GitHub Actions       | CI/CD workflows and automation                        | YAML     | Supported      |
| `docs/`, wiki, README | End-user documentation                               | Markdown | Supported      |
| Web interface        | Landing page and releases browser                     | HTML/JS  | Supported      |

**Out of scope:** Third-party software (Proxmox VE, Debian, driverctl, ROCm, NVIDIA drivers, etc.) must be reported to their respective upstream maintainers.

---

## 2. Supported Versions

**View all releases:** [Browse complete release history](https://danilop95.github.io/Proxmox-Enhanced-Configuration-Utility/releases.html)

| PECU Channel | Security Support | Support Duration | Description |
|--------------|------------------|------------------|-------------|
| **Stable**   | **Full support** | 12 months | Complete security updates, bug fixes, and feature updates |
| **Legacy**   | **Critical fixes only** | 6 months | Critical security patches and major bug fixes only |
| **Beta**     | **No security support** | N/A | Development versions for testing purposes |
| **Experimental** | **No security support** | N/A | Unstable features and proof-of-concept implementations |
| **Deprecated** | **End of support** | N/A | No security updates or bug fixes provided |

### Support Policy Details

- **Stable Channel:** Latest stable releases receive comprehensive security support including all vulnerability patches, security enhancements, and compatibility updates
- **Legacy Channel:** Previous stable versions receive only critical security fixes (CVSS >= 7.0) for a limited period
- **Development Channels:** Beta and experimental releases are not supported for security issues and should not be used in production environments
- **End of Life:** Deprecated versions receive no security updates and users must upgrade to supported versions

**Important:** Vulnerabilities in unsupported versions will not be patched. Organizations must upgrade to supported releases to maintain security coverage.

---

## 3. Reporting Security Vulnerabilities

### Private Disclosure Process

**Primary Method: GitHub Security Advisories**
1. Navigate to the [Security tab](https://github.com/Danilop95/Proxmox-Enhanced-Configuration-Utility/security)
2. Select "Report a vulnerability"
3. Complete the advisory form with comprehensive details

**Alternative Method: Email Disclosure**
- Contact: **security@dvnilxp.dev**
- PGP encryption recommended (key available upon request)
- Include all required information detailed below

### Required Vulnerability Information

```
Subject: [SECURITY] PECU Vulnerability Report

1. Vulnerability Description:
   - Detailed technical description of the security issue
   - Attack vector and exploitation methodology
   - Potential impact assessment and affected systems

2. Affected Components:
   - PECU version or release tag
   - Specific scripts or components affected
   - Proxmox VE version compatibility

3. System Environment:
   - Operating system and kernel version
   - Hardware configuration details
   - Network configuration if relevant

4. Reproduction Information:
   - Step-by-step reproduction instructions
   - Required privileges or system state
   - Expected vs actual behavior

5. Supporting Evidence:
   - Proof-of-concept code or commands
   - Log files or error messages
   - Screenshots or system output

6. Suggested Remediation:
   - Proposed fix or mitigation strategy
   - Workaround procedures if available
   - Impact assessment of proposed changes

7. Disclosure Preferences:
   - Attribution preferences (credited or anonymous)
   - Coordinated disclosure timeline requirements
```

### Response Timeline Commitments

| Phase | Standard Timeline | Critical Timeline | Description |
|-------|------------------|-------------------|-------------|
| **Initial Response** | 48 hours | 24 hours | Acknowledgment of vulnerability report |
| **Preliminary Assessment** | 7 days | 72 hours | Initial impact and severity evaluation |
| **Detailed Analysis** | 14 days | 7 days | Complete vulnerability analysis and CVSS scoring |
| **Fix Development** | 30 days | 14 days | Patch development and internal testing |
| **Public Disclosure** | 90 days | 30 days | Coordinated public advisory and release |

*Critical vulnerabilities are defined as CVSS >= 8.0 or those with active exploitation*

---

## 4. Security Patch Development Process

### Standard Vulnerability Response

| Phase | Objective | Timeline | Deliverables |
|-------|-----------|----------|--------------|
| **Triage** | Validate and categorize vulnerability | 1-3 days | Severity assessment, CVSS score |
| **Analysis** | Detailed impact and root cause analysis | 3-7 days | Technical analysis, affected versions |
| **Development** | Create and test security patch | 7-21 days | Patched code, regression testing |
| **Review** | Security review and quality assurance | 2-5 days | Code review, security validation |
| **Release** | Deploy patch and update documentation | 1-2 days | Security release, advisory publication |
| **Post-Release** | Monitor deployment and gather feedback | Ongoing | Community feedback, additional fixes |

### Critical Vulnerability Response

For vulnerabilities meeting critical criteria:
- **Immediate escalation** to primary maintainer
- **24/7 response capability** during business hours
- **Expedited development timeline** with dedicated resources
- **Emergency release process** bypassing standard release cycles
- **Coordinated disclosure** with major distributions and users

---

## 5. Security Architecture and Controls

### Code Security Measures

**Input Validation and Sanitization**
- All user inputs undergo strict validation and sanitization
- Regular expression patterns for system identifiers and paths
- Boundary checking for numerical inputs and system limits

**Secure Coding Practices**
- Bash strict mode (`set -Eeuo pipefail`) enforced across all scripts
- Explicit error handling with detailed logging and recovery procedures
- Minimal privilege principle with targeted sudo usage

**Path and File Security**
- Absolute path requirements for all file operations
- Directory traversal prevention through path validation
- Temporary file creation with secure permissions and cleanup

### System Security Controls

**Backup and Recovery**
- Automatic system state backup before configuration changes
- Rollback mechanisms for failed or problematic configurations
- Configuration versioning and change tracking

**Audit and Logging**
- Comprehensive logging to `/var/log/pecu.log` with rotation
- Security event logging including authentication and authorization
- Audit trail maintenance for forensic analysis capabilities

**Hardware Validation**
- PCI device ID format validation and existence verification
- Hardware compatibility checking before configuration changes
- System resource validation and capacity planning

### Release Security Framework

**Code Signing and Verification**
- GPG signing of all release tags and distribution packages
- SHA256 checksum generation and verification for all assets
- Cryptographic integrity verification throughout distribution chain

**Release Channel Management**
- Strict separation between stable, beta, and experimental channels
- Automated testing and validation before channel promotion
- Clear documentation of channel-specific security policies

**Dependency Management**
- Minimal external dependency requirements with version pinning
- Regular security scanning of dependencies and base systems
- Automated vulnerability detection in dependency chain

---

## 6. Verification and Validation Procedures

### Release Verification Commands

```
# Verify GPG signature of release tag
git verify-tag v2025.06.20

# Validate script integrity using checksums
sha256sum -c checksums.txt

# Verify detached GPG signature
gpg --verify proxmox-configurator.sh.asc proxmox-configurator.sh

# Check commit signature history
git log --show-signature --oneline
```

### Security Validation Checklist

**Pre-Installation Verification**
- Verify GPG signatures of downloaded scripts
- Validate checksums against published values
- Review script contents for unexpected modifications
- Confirm system compatibility and requirements

**Post-Installation Validation**
- Review generated configuration files
- Verify system logs for errors or warnings
- Test rollback procedures in non-production environment
- Validate security controls and access restrictions

---

## 7. User Security Guidelines

### Production Environment Recommendations

**Mandatory Security Practices**
- Use only stable channel releases in production systems
- Verify all downloads using provided cryptographic signatures
- Maintain current backups before executing configuration changes
- Test all changes in isolated development environments first

**Access Control Requirements**
- Limit administrative access to authorized personnel only
- Implement multi-factor authentication for system access
- Maintain audit logs of all administrative activities
- Regular review of user access and permissions


### Security Incident Response

**Immediate Actions**
- Preserve system logs and evidence for analysis
- Contact security team using established communication channels
- Document all actions taken during incident response

**Recovery Procedures**
- Use automated rollback capabilities to restore known-good state
- Verify system integrity using checksums and signatures
- Apply security patches before returning systems to production
- Conduct post-incident review and documentation

---

## 8. Exclusions and Limitations

### Out-of-Scope Security Issues

**External Software Components**
- Vulnerabilities in Proxmox VE platform or underlying Debian system
- Security issues in proprietary GPU drivers or firmware
- Kernel vulnerabilities or hardware-specific security flaws
- Third-party package vulnerabilities in system dependencies

**User Configuration Issues**
- Security misconfigurations introduced by end users
- Unauthorized modifications to PECU scripts or configurations
- Insecure system configurations outside PECU's scope
- Hardware misconfigurations or compatibility issues

**Infrastructure and Platform Issues**
- GitHub platform security vulnerabilities
- DNS, CDN, or hosting provider security issues
- Client-side browser or operating system vulnerabilities

### Limitation of Liability

This security policy covers only the PECU software components directly maintained by the project team. Users are responsible for:
- Maintaining secure system configurations
- Applying security updates to underlying systems
- Following established security best practices
- Reporting suspected security issues promptly

---

## 9. Security Community Recognition

### Acknowledgment Process

Security researchers who responsibly disclose vulnerabilities receive recognition through:

**Public Acknowledgment**
- Credit in release notes and security advisories
- Recognition in project documentation and website
- Optional CVE co-credit for significant discoveries

**Hall of Fame Recognition**
- Dedicated security contributors page
- Annual recognition for outstanding contributions
- Conference presentation opportunities where applicable

**Communication and Feedback**
- Direct communication with project maintainers
- Feedback on security improvements and suggestions
- Invitation to participate in security review processes

### Recognition Criteria

| Contribution Level | Recognition Type | Criteria |
|-------------------|------------------|----------|
| **Critical** | Featured acknowledgment | CVSS >= 8.0 or active exploitation |
| **High** | Standard acknowledgment | CVSS 6.0-7.9 with significant impact |
| **Medium** | Contributor recognition | CVSS 4.0-5.9 or security improvements |
| **Low** | Documentation credit | Minor issues or documentation improvements |

Anonymity preferences are respected and maintained throughout the recognition process.

---

## 10. Cryptographic Standards and Key Management

### GPG Signing Infrastructure

**Primary Signing Key**
\`\`\`
Key ID: 3AA5C34371567BD2
Algorithm: RSA 4096-bit
Created: 2024-01-15
Expires: 2026-01-15
Fingerprint: 1234 5678 9ABC DEF0 1234 5678 3AA5 C343 7156 7BD2
\`\`\`

**Key Distribution and Verification**
\`\`\`bash
# Import from Ubuntu keyserver
gpg --keyserver keyserver.ubuntu.com --recv-keys 3AA5C34371567BD2

# Import from GitHub
curl -sL https://github.com/Danilop95.gpg | gpg --import

# Verify key fingerprint
gpg --fingerprint 3AA5C34371567BD2
\`\`\`

**Signature Verification Examples**
\`\`\`bash
# Verify release tag signature
git verify-tag v2025.06.20

# Verify script signature
gpg --verify proxmox-configurator.sh.sig proxmox-configurator.sh

# Verify checksum file signature
gpg --verify SHA256SUMS.asc SHA256SUMS
\`\`\`

### Cryptographic Standards Compliance

**Hash Algorithms**
- SHA-256 for file integrity verification
- SHA-512 for password hashing where applicable
- Blake2b for high-performance hashing requirements

**Signature Algorithms**
- RSA-4096 for release signing and verification
- Ed25519 for commit signing where supported
- ECDSA P-384 for alternative signature verification

---

## 11. Compliance and Regulatory Alignment

### Security Framework Compliance

**Industry Standards**
- OWASP Secure Coding Practices for script development
- CIS Controls for Linux system hardening recommendations
- NIST Cybersecurity Framework alignment for risk management
- ISO 27001 security management principles integration

**Regulatory Considerations**
- GDPR compliance for any personal data handling
- SOX compliance considerations for financial environments
- HIPAA awareness for healthcare system deployments
- PCI DSS considerations for payment processing environments

### Audit and Assessment Schedule

**Regular Security Activities**
- Monthly automated vulnerability scanning
- Quarterly manual security code review
- Semi-annual penetration testing assessment
- Annual third-party security audit

**Continuous Monitoring**
- Real-time dependency vulnerability monitoring
- Automated security testing in CI/CD pipeline
- Community vulnerability report monitoring
- Threat intelligence integration and analysis

---

## 12. Contact Information and Resources

### Security Team Contacts

**Primary Security Contact**
- Maintainer: [@Danilop95](https://github.com/Danilop95)
- Email: security@dvnilxp.dev
- Response Hours: Monday-Friday, 09:00-17:00 CET
- Emergency Response: Available for critical vulnerabilities

**Alternative Communication Channels**
- GitHub Security Advisories (preferred for vulnerability reports)
- GitHub Issues (for non-sensitive security discussions)
- Project Discussions (for security-related questions)

### Project Resources

**Documentation and Information**
- Project Homepage: [PECU Landing Page](https://danilop95.github.io/Proxmox-Enhanced-Configuration-Utility/)
- Release Browser: [All Releases](https://danilop95.github.io/Proxmox-Enhanced-Configuration-Utility/releases.html)
- Issue Tracker: [GitHub Issues](https://github.com/Danilop95/Proxmox-Enhanced-Configuration-Utility/issues)
- Community Forum: [GitHub Discussions](https://github.com/Danilop95/Proxmox-Enhanced-Configuration-Utility/discussions)

**Security-Specific Resources**
- Security Advisories: [GitHub Security Tab](https://github.com/Danilop95/Proxmox-Enhanced-Configuration-Utility/security)
- Vulnerability Database: [GitHub Advisory Database](https://github.com/advisories)
- Security Best Practices: [Project Wiki](https://github.com/Danilop95/Proxmox-Enhanced-Configuration-Utility/wiki)

---

## 13. Policy Governance and Updates

### Document Management

This security policy is maintained under version control and updated regularly to reflect:
- Changes in project scope and architecture
- Evolution of security threats and best practices
- Community feedback and security research findings
- Regulatory and compliance requirement updates

### Version History

| Version | Date | Significant Changes |
|---------|------|-------------------|
| 3.0 | 2025-06-20 | Complete policy restructure, enhanced security controls |
| 2.1 | 2025-06-17 | Added release browser integration, updated support matrix |
| 2.0 | 2025-04-15 | Major revision with industry standard alignment |
| 1.1 | 2025-02-01 | Added cryptographic verification procedures |
| 1.0 | 2025-01-15 | Initial security policy establishment |

### Review and Update Schedule

**Regular Review Cycle**
- Quarterly review of policy effectiveness and relevance
- Annual comprehensive policy update and revision
- Ad-hoc updates for significant security events or changes
- Community input integration and feedback incorporation

**Change Management Process**
- All policy changes tracked in version control system
- Security team review and approval for all modifications
- Community notification for significant policy changes
- Backward compatibility considerations for existing processes

---

**Document Information**
- **Last Updated:** June 20, 2025
- **Next Scheduled Review:** September 20, 2025
- **Policy Version:** 3.0
- **Effective Date:** June 20, 2025

---

*This security policy is maintained in accordance with industry best practices for open source software security and responsible disclosure principles.*
