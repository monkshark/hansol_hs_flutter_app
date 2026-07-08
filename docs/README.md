# API Reference - 목차

> 화면(Screen)·위젯(Widget) 문서는 제외. 서비스·모델·API·알림 등 핵심 계층만 정리
>
> 주제별 가이드(아키텍처, 데이터 모델, 테스트, 보안 등)는 [`guides/`](./guides/), 기능별 상세는 [`features/`](./features/) 참조

## 앱 진입점
- [main](./main.md) — 앱 초기화, MainScreen, 전역 상태

## API 계층 (lib/api/)
- [meal_data_api](./reference/meal/meal_data_api.md) — NEIS 급식 API, 월간 프리페치, 24h/5min 캐시
- [notice_data_api](./reference/notice/notice_data_api.md) — NEIS 학사일정 API, 예정 이벤트, 12h 캐시
- [timetable_data_api](./reference/timetable/timetable_data_api.md) — NEIS 시간표 API, 과목 조합, 12h 캐시

## 데이터 계층 (lib/data/)
- [auth_service](./reference/auth/auth_service.md) — 소셜 로그인 4종, 프로필 CRUD, 5분 캐시
- [auth_repository](./reference/auth/auth_repository.md) — AuthRepository 인터페이스, GetIt DI
- [grade_manager](./reference/grade/grade_manager.md) — 성적 CRUD, 목표 관리, 등급 변환
- [grade_repository](./reference/grade/grade_repository.md) — GradeRepository 인터페이스, GetIt DI
- [dday_manager](./reference/dday/dday_manager.md) — D-day CRUD, Firestore 동기화
- [local_database](./reference/common/local_database.md) — SQLite 일정 DB, Firestore 동기화
- [subject_data_manager](./reference/grade/subject_data_manager.md) — 선택과목 로드/저장
- [search_tokens](./reference/search/search_tokens.md) — 한국어 2-gram 토큰화
- [search_history_service](./reference/search/search_history_service.md) — 검색 기록 (최대 10개)
- [secure_storage_service](./reference/common/secure_storage_service.md) — 암호화 저장소 래퍼
- [analytics_service](./reference/common/analytics_service.md) — Firebase Analytics 이벤트 래퍼
- [setting_data](./reference/settings/setting_data.md) — SharedPreferences 설정 싱글톤
- [service_locator](./reference/common/service_locator.md) — GetIt DI 설정
- [meal](./reference/meal/meal.md) — Meal 데이터 모델 (freezed)
- [schedule_data](./reference/timetable/schedule_data.md) — Schedule 데이터 모델
- [subject](./reference/grade/subject.md) — Subject 데이터 모델 (freezed)
- [device](./reference/common/device.md) — 디바이스 크기 계산 유틸리티
- [api_strings](./reference/common/api_strings.md) — API 센티널 문자열 상수 (데이터 유무 판별용)
- [board_categories](./reference/community/board_categories.md) — 게시판 카테고리 상수 + l10n/색상/FCM 토픽 헬퍼
- [post_repository](./reference/community/post_repository.md) — 게시판 Firestore CRUD 싱글턴

## 알림 (lib/notification/)
- [fcm_service](./reference/notification/fcm_service.md) — FCM 푸시 알림, 토픽, 딥링크
- [daily_meal_notification](./reference/meal/daily_meal_notification.md) — 로컬 급식 알림 스케줄링
- [popup_notice](./reference/notice/popup_notice.md) — 인앱 팝업 공지
- [update_checker](./reference/common/update_checker.md) — 앱 버전 체크

## 상태 관리 (lib/providers/)
- [providers](./reference/common/providers.md) — Riverpod Notifier/AsyncNotifier 전체

## 스타일 (lib/styles/)
- [app_colors](./reference/common/app_colors.md) — 테마 컬러 + AnimatedAppColors
- [dark_app_colors](./reference/common/dark_app_colors.md) — 다크 테마 색상 구현체
- [light_app_colors](./reference/common/light_app_colors.md) — 라이트 테마 색상 구현체

## 네트워크 (lib/network/)
- [network_status](./reference/common/network_status.md) — 네트워크 연결 상태 스트림
- [offline_queue_manager](./reference/common/offline_queue_manager.md) — 오프라인 쓰기 큐 (sqflite)
