# Minimal 30-row cell-aware VT screen for setup and real Bubble Tea.
# Return text rows by default, or raw cells with --argjson cell_screen true.
def cells:
  if (.>=4448 and .<=4607) or (.>=768 and .<=879) or
     (.>=65024 and .<=65039) or (.>=8203 and .<=8207) then 0
  elif (.>=4352 and .<=4447) or (.>=11904 and .<=42191) or
       (.>=44032 and .<=55203) or (.>=65281 and .<=65376) or
       (.>=127744 and .<=129791) or (.>=9728 and .<=10175) then 2 else 1 end;
[scan("\u001b\\][^\u0007\u001b]*(?:\u0007|\u001b\\\\)|\u001b\\[[0-?]*[ -/]*[@-~]|[^\u001b]";"s")] |
reduce .[] as $token ({row:0,column:0,saved:null,screen:[range(0;30)|[]]};
  if $token=="\u001b[s" then .saved={row,column}
  elif $token=="\u001b[u" then if .saved!=null then .row=.saved.row|.column=.saved.column else . end
  elif ($token|test("^\u001b\\[[0-9]*A$")) then
    ($token|capture("\\[(?<count>[0-9]*)A").count|if .=="" then 1 else tonumber end) as $count | .row=([0,.row-$count]|max)
  elif ($token|test("^\u001b\\[[0-9]*[BCD]$")) then
    ($token|capture("\\[(?<count>[0-9]*)(?<direction>[BCD])")) as $move |
    ($move.count|if .=="" then 1 else tonumber end) as $count |
    if $move.direction=="B" then .row=([29,.row+$count]|min)
    elif $move.direction=="C" then .column+=$count
    else .column=([0,.column-$count]|max) end
  elif ($token|test("^\u001b\\[[0-9;]*[Hf]$")) then
    ($token|ltrimstr("\u001b[")|.[0:-1]|split(";")|map(if .=="" then 1 else tonumber end)) as $position |
    .row=([29,([0,($position[0] // 1)-1]|max)]|min) |
    .column=([0,($position[1] // 1)-1]|max)
  elif ($token|test("^\u001b\\[[0-9]*G$")) then
    .column=($token|capture("\\[(?<column>[0-9]*)G").column|if .=="" then 0 else ([0,tonumber-1]|max) end)
  elif $token=="\u001b[2K" then .screen[.row]=[]
  elif $token=="\u001b[K" or $token=="\u001b[0K" then .screen[.row]=.screen[.row][:.column]
  elif $token=="\u001b[J" or $token=="\u001b[0J" then
    .screen[.row]=.screen[.row][:.column] |
    .row as $row | .screen|=(to_entries|map(if .key>$row then [] else .value end))
  elif $token=="\u001b[2J" then .screen=[range(0;30)|[]]
  elif ($token|startswith("\u001b")) then .
  elif $token=="\r" then .column=0
  elif $token=="\n" then
    if .row==29 then .screen=.screen[1:]+[[]] else .row+=1 end
  elif $token=="\b" then .column=([0,.column-1]|max)
  elif $token=="\t" then .column+=(8-(.column%8))
  elif ($token|explode[0]|cells)==0 then
    if .column>0 then
      .row as $row | (.column-1) as $last |
      (if .screen[$row][$last]=="" and $last>0 then $last-1 else $last end) as $base |
      .screen[$row][$base]+=$token
    else . end
  else
    ($token|explode[0]|cells) as $width |
    .screen[.row][.column]=$token |
    if $width==2 then .screen[.row][.column+1]="" else . end |
    .column+=$width
  end) | .screen |
if $ARGS.named.cell_screen // false then . else map(map(. // " ")|join("")) end
