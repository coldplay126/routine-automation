include "jira";
($prompt|split("\n")|map(select(startswith("- ") and contains(" 예: "))|capture(" 예: (?<value>.+)$").value|fromjson)) as $examples |
{merge:[$examples[0]],attach:[$examples[1]],links:[$examples[2]],create:[$examples[3]],sections:[$examples[4]]} as $canonical |
($canonical|tojson) as $json |
($schema[0].properties) as $properties |
# Prompt examples and the unchanged Claude schema agree on every fixed field.
($examples|length)==5 and ($canonical|jira_llm_ok) and
($schema[0].required|sort)==($canonical|keys) and $schema[0].additionalProperties==false and
$properties.merge.items.type=="array" and $properties.merge.items.minItems==2 and
all(["attach","links","create","sections"][];. as $kind|
  ($canonical[$kind][0]|keys)==($properties[$kind].items.required|sort) and $properties[$kind].items.additionalProperties==false) and
($canonical.sections[0].lines[0]|keys)==($properties.sections.items.properties.lines.items.required|sort) and
$properties.sections.items.properties.lines.items.additionalProperties==false and
$properties.sections.items.properties.lines.items.properties.evidence.minItems==1 and
([$properties.merge.maxItems,$properties.attach.maxItems,$properties.links.maxItems,$properties.create.maxItems,
  $properties.links.items.properties.reason.maxLength,$properties.create.items.properties.summary.maxLength,
  $properties.sections.items.properties.lines.maxItems,$properties.sections.items.properties.lines.items.properties.text.maxLength]==[20,100,30,30,300,120,10,300]) and
# Known variants preserve the same values; normalization never supplies IDs or text.
all([
  $canonical,
  ($canonical|.merge|=map({works:.,reason:"ignored metadata"})),
  ($canonical|.merge|=map({ids:.,reason:"ignored metadata",evidence:[]})),
  ($canonical|.attach|=map({work,report:.evidence,reason:"ignored metadata"})),
  ($canonical|.attach|=map(.reason="ignored metadata")|.links|=map(.evidence=[])|.create|=map(.reason="ignored metadata"|.evidence=[]))
][];(.|jira_llm_normalize)==$canonical and (.|jira_llm_normalize|jira_llm_ok)) and
# Unknown aliases, conflicting aliases and other surplus fields remain invalid.
all([
  ($canonical|.merge|=map({members:.})),
  ($canonical|.merge|=map({works:.,ids:.})),
  ($canonical|.attach[0].report=.attach[0].evidence),
  ($canonical|.attach|=map(.proof=.evidence|del(.evidence))),
  ($canonical|.links[0].extra="unknown"),
  ($canonical|.create[0].summary={text:"unknown"}),
  ($canonical|.sections[0].reason="not supported"),
  ($canonical|.extra=[]),
  ($canonical|del(.merge)),
  []
][];try (jira_llm_normalize|jira_llm_ok|not) catch true) and
all([$json," \n"+$json+"\t\n","```json\n"+$json+"\n```","```\n"+$json+"\n```",
  "```JSON\n"+$json+"\n```","``` json\n"+$json+"\n```"," \t``` JsOn\t\r\n"+$json+"\r\n \t```\t\r\n",
  "설명문\n```json\n"+$json+"\n```\n추가 설명문","[참고] 결과:\n```json\n"+$json+"\n```\n[w-a]는 제외"
][];jira_llm_json==$canonical) and
# Only standalone fence lines are boundaries; quotes, escapes and inline backticks are data.
(($canonical|.links[0].reason="문자 } {와 \"인용\" 및 \\ 경로·코드 ``` 표기") as $quoted |
  all([($quoted|tojson),"```json\n"+($quoted|tojson)+"\n```",
    "설명 ``` 표기\n``` JSON\r\n"+($quoted|tojson)+"\r\n```\r\n끝 ``` 표기"
  ][];jira_llm_json==$quoted)) and
# Bare objects in prose, multiple values/fences and malformed containers are non-JSON.
all([
  $json+"\n"+$json,"```json\n"+$json+"\n```\n"+$json,$json+"\n```\n"+$json+"\n```",
  "```json\n"+$json+"\n```\n```json\n"+$json+"\n```","```python\n"+$json+"\n```","```json\n"+$json,
  "```json\n"+$json+"```","```json\n"+$json+"\n```JSON","```json\n"+$json+"\n``` 끝",
  "```\n"+$json+"\n```\n```\n"+$json+"\n```","```json\n"+$json+"\n```\n```",
  "설명문\n"+$json+"\n추가 설명문","[참고] 결과: "+$json+"\n[w-a]는 제외","메모 {표기\n"+$json+"\n후속 {설명",
  "설명\n{\"result\":"+$json,"{\"result\":"+$json+",broken}","[broken,"+$json+"]",
  "설명만","", "["+$json+"]","설명\n["+$json+"]","설명\n[["+$json+"]]",
  "설명\n```json\n["+$json+"]\n```","설명\n[0,"+$json+"]","설명\n[\"first\","+$json+"]",
  "설명\n["+$json,"설명\n[0,"+$json+",broken]","null","true","0","\"text\"",
  "```json\n{\"result\":"+$json+"\n```","```json\n{\"result\":"+$json+",broken}\n```","```\n[broken,"+$json+"]\n```",
  # An outer fence of another language (or a longer fence) hides an inner json fence; reject, never unwrap.
  "```python\n```json\n"+$json+"\n```","```other\n```json\n"+$json+"\n```\n```","````python\n```json\n"+$json+"\n```\n````"
][];try (jira_llm_json|false) catch true)
