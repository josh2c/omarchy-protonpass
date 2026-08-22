#!/usr/bin/env bash
# Shapes shared by the mocks and the test suites, so a contract cannot drift
# between the thing that produces fixture data and the thing that asserts on
# it. The helper itself stays self-contained and never reads this file.
#
# jq expressions are written for the value they describe: the template shape
# and the recents entry shape apply to an object, the password policy applies
# to a password string.

FIXTURE_PASSWORD_LENGTH=24

FIXTURE_PASSWORD_POLICY='type == "string" and length == '"$FIXTURE_PASSWORD_LENGTH"' and
  test("^[A-Za-z0-9!@#$%^&*()_+=-]+$") and
  test("[A-Z]") and test("[a-z]") and test("[0-9]") and
  test("[!@#$%^&*()_+=-]")'

FIXTURE_CREATE_TEMPLATE_SHAPE='type == "object" and
  (keys | sort) == ["email", "password", "title", "totp_uri", "urls", "username"] and
  (.title | type == "string" and length > 0 and length <= 500) and
  (((.username | type == "string" and length <= 500) and .email == null) or
   ((.email | type == "string" and length <= 500) and .username == null)) and
  (.password | '"$FIXTURE_PASSWORD_POLICY"') and
  .totp_uri == null and .urls == []'

FIXTURE_RECENTS_ENTRY_SHAPE='(keys | sort) == ["itemId", "shareId", "ts"] and
  (.shareId | type == "string" and test("^[A-Za-z0-9+/=_-]{1,256}$")) and
  (.itemId | type == "string" and test("^[A-Za-z0-9+/=_-]{1,256}$")) and
  (.ts | type == "number" and . >= 0 and floor == .)'

# Bash ERE counterparts of the password policy, for assertions that run against
# a generated password directly rather than through jq.
FIXTURE_PASSWORD_CHARSET_REGEX='^[A-Za-z0-9!@#$%^&*()_+=-]+$'
FIXTURE_PASSWORD_SYMBOL_REGEX='[!@#$%^&*()_+=-]'
