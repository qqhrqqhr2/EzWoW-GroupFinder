# v1.0.9

### 한국어
- 데이터 공유 현황 창을 추가했습니다. `/공유` 또는 `/ezshare`로 열면 받은 기록, 보낸 사람, 보낸 기록, 종류별 현황과 새로 받은 기록만 따로 볼 수 있습니다.
- 공유 데이터를 채널로도 보내 더 빨리 퍼지게 했습니다.
- 데이터 채널의 사용자 명단이 새로 갱신되지 않아 일부 사용자와 귓속말로 공유 기록을 주고받지 못하던 문제를 고쳤습니다.
- 퀘스트 보상, 트레이너가 가르치는 주문, 오브젝트 이름도 다른 사용자와 공유합니다.
- 게임패드: 전투가 끝나면 EzWoW 창이 패드 조작을 가져가던 문제를 고쳤습니다. 전투 전에 EzWoW 창을 조작하던 경우에만 되돌립니다.
- 파티찾기 채널에서 나가도 로딩 화면마다 다시 들어가던 문제를 고쳤습니다. 나간 상태는 다시 불러오기 뒤에도 유지되고, 새로 접속하면 다시 들어갑니다.
- "파티구성", "파티 구인" 같은 모집 글이 구직 글로 분류되던 문제를 고쳤습니다.
- "DM:E", "Zul'Farrak"처럼 기호가 들어간 영어 던전 이름을 알아보지 못하던 문제를 고쳤습니다.
- 같은 사람이 모집 글을 다시 올리면 5분이 지난 뒤부터 매번 알림음이 울리던 문제를 고쳤습니다.
- 사용자 채널이 공개 채널보다 먼저 들어가 채널 번호를 밀어내던 문제와, 전투 중이라 건너뛴 채널 순서 정리를 다시 하지 않던 문제를 고쳤습니다.
- 한국어 채팅 줄마다 영어 단어를 검사하던 부담을 줄였습니다.
- 공유 기록을 설치된 EzWoW 애드온 중 최대 2개에만 저장해 접속·다시 불러오기가 빨라지고 저장 파일이 작아집니다. 업데이트 후 게임을 한 번 완전히 다시 시작하면 적용됩니다.

### English
- Added a data sharing window. Open it with `/ezshare` to see received records, players, sent records, totals by kind, and only the newly received records.
- Shared data is now also sent through the channel, so it spreads faster.
- Fixed shared records not being exchanged by whisper with some players because the data channel's player list was not refreshed.
- Quest rewards, trainer spells and object names are now shared with other players too.
- Gamepad: EzWoW windows no longer take over the pad after combat; it returns only if you were using an EzWoW window before the fight.
- Fixed rejoining the LFG channel after every loading screen once you had left it. Leaving now lasts through reloads; a new login joins again.
- Fixed recruiting posts such as "파티구성" or "파티 구인" being listed as players looking for a group.
- Fixed English dungeon names with punctuation, such as "DM:E" or "Zul'Farrak", not being recognized.
- Fixed the alert sound playing on every repost once 5 minutes had passed.
- Fixed custom channels joining before General and taking its number, and the channel order fix not being retried after combat.
- Reduced the cost of checking each Korean chat line for English words.
- Shared records are now saved by at most 2 of your installed EzWoW addons, so logins and reloads are faster and save files smaller. Takes effect after one full game restart following the update.
