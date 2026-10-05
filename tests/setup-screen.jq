# The user-facing setup checklist appears once, in execution order.
def setup_rows:
  [ .[] | capture("^(?<marker>[○●✓–✗·⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏]) (?<label>플랫폼 확인|필수 도구|GitHub 로그인|LLM 엔진|Slack 앱|Orca 권한|전체 디스크 접근|설정 저장|예약 실행 등록|첫 실행)(?<detail> .*|)$")? ];
def setup_once:
  setup_rows | map(.label)==["플랫폼 확인","필수 도구","GitHub 로그인","LLM 엔진","Slack 앱","Orca 권한","전체 디스크 접근","설정 저장","예약 실행 등록","첫 실행"];
