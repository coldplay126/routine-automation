def redact_url:
  gsub("://[^/[:space:]:@]+:[^/[:space:]@]+@"; "://[REDACTED]@");
def redact_presigned:
  gsub("(?<k>X-Amz-Credential|X-Amz-Signature|X-Amz-Security-Token|AWSAccessKeyId|Signature)=[^&[:space:]\"]+"; "\(.k)=[REDACTED]"; "i");
def redact:
  redact_url | redact_presigned |
  gsub("(?i)Bearer[[:space:]]+[^[:space:]]+"; "Bearer [REDACTED]") |
  gsub("(?i)\"?[A-Za-z_]*(token|password|secret|(api|secret|access|private)[_-]?key)\"?[[:space:]]*[:=][[:space:]]*\"?[^[:space:]\",}]+\"?"; "[REDACTED]") |
  gsub("(AKIA|ASIA)[0-9A-Z]{16}|\\bgithub_pat_[A-Za-z0-9_]{20,}|xox[abprs]-[A-Za-z0-9_-]+|ATATT[A-Za-z0-9_=+/.-]+|eyJ[A-Za-z0-9_-]+[.][A-Za-z0-9_-]+[.][A-Za-z0-9_-]+|\\bgh[pousr]_[A-Za-z0-9_-]{20,}|\\bsk-[A-Za-z0-9_-]{20,}"; "[REDACTED]") |
  gsub("-----BEGIN [A-Z ]*PRIVATE KEY-----[\\s\\S]*?(-----END [A-Z ]*PRIVATE KEY-----|$)"; "[REDACTED]");
