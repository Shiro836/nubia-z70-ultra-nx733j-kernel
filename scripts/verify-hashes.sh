#!/usr/bin/env bash
# Verify pinned hashes for this recipe and for artifacts built from it.
#
# Usage:
#   ./scripts/verify-hashes.sh                 # check the configs shipped here
#   ./scripts/verify-hashes.sh artifacts DIR VARIANT
#   ./scripts/verify-hashes.sh boot IMAGE     VARIANT
#
# VARIANT: stock | sukisu_only | full | control
#
# "stock" is the unmodified GKI build. "control" is the Docker/systemd-only
# build (no SukiSU). The artifacts directory must contain Image, config and
# Module.symvers. Only files that exist are checked; missing files are reported
# as skipped.
set -uo pipefail

fail=0
check() {
  local file="$1" expected="$2" actual
  if [ ! -f "$file" ]; then
    echo "SKIP    $file (missing)"
    return 0
  fi
  actual=$(sha256sum "$file" | awk '{print $1}')
  if [ "$actual" = "$expected" ]; then
    echo "OK      $file  $actual"
  else
    echo "FAIL    $file"
    echo "        expected $expected"
    echo "        actual   $actual"
    fail=$((fail + 1))
  fi
}

MODE="${1:-configs}"

case "$MODE" in
  configs)
    echo "== shipped configs =="
    check "configs/stock.config"                "f21f8de739dc13dd5af6fda290ab62322968836af5133f4cb32c02c1a4f6ff18"
    check "configs/sukisu_only.config"          "b3910c8ebb4e87f7070d54aa8f267a57462d2d78b1afc8fc6968593142a9a10c"
    check "configs/full.config"                 "d90af3c0424fe651751c00e479e8c500c01b9c857ea4a451894c8d400c089f1e"
    check "configs/docker_systemd_v2.fragment"  "7c987b8a8de0480c5fd7c3baf75ca060356c10992333075842cbd8392e0d90fd"
    check "configs/sukisu.fragment"             "fd0fd1a95396ac1a4f2e4ad4afcd86bafdf5322bb6a8a72f89b5d8966888cf24"
    ;;

  artifacts)
    DIR="${2:?usage: verify-hashes.sh artifacts DIR VARIANT}"
    VARIANT="${3:?usage: verify-hashes.sh artifacts DIR VARIANT}"
    echo "== artifacts in $DIR ($VARIANT) =="
    case "$VARIANT" in
      stock)
        check "$DIR/Image"             "11bf8868967b8f1657f9364afd48e0be2a351736485994fb5efae21aef595896"
        check "$DIR/config"            "f21f8de739dc13dd5af6fda290ab62322968836af5133f4cb32c02c1a4f6ff18"
        ;;
      sukisu_only)
        check "$DIR/Image"             "241945762e191b45a6cce8da07b2505bde9ad0e4d1899bf32fe3e2aaf470f16d"
        check "$DIR/config"            "b3910c8ebb4e87f7070d54aa8f267a57462d2d78b1afc8fc6968593142a9a10c"
        check "$DIR/Module.symvers"    "5139c8777949c23c5b7ccc5624099bb6d7ead4275f8515df8db81c1c2228d490"
        ;;
      full)
        check "$DIR/Image"             "5735e5dd219d159b155557e61379d381baad936bfb03052e6ffb86f202191e11"
        check "$DIR/config"            "d90af3c0424fe651751c00e479e8c500c01b9c857ea4a451894c8d400c089f1e"
        check "$DIR/Module.symvers"    "e0785b239df0a4123c859fe7939adfe6d048a343098572bb998642fe78d1aca1"
        ;;
      control)
        check "$DIR/Image"             "22a4275cce10bc8b85ed94aa822b54a6e3f80f87b70c37e177c8d0ca5eb71a2d"
        check "$DIR/config"            "182a72756294b93e89869f98295d9ef8ade0cde919c5ac203078795efdd36675"
        check "$DIR/Module.symvers"    "e0785b239df0a4123c859fe7939adfe6d048a343098572bb998642fe78d1aca1"
        ;;
      *) echo "unknown variant: $VARIANT" >&2; exit 2 ;;
    esac
    ;;

  boot)
    IMAGE="${2:?usage: verify-hashes.sh boot IMAGE VARIANT}"
    VARIANT="${3:?usage: verify-hashes.sh boot IMAGE VARIANT}"
    echo "== boot image $IMAGE ($VARIANT) =="
    case "$VARIANT" in
      sukisu_only) check "$IMAGE" "742ac0987601a36aec428cdf3975a46e1aab56a4f9abfb331359260e8f851158" ;;
      full)        check "$IMAGE" "c9b7834b4b58699456bff49d73511c5cf321f853ecc96fa246223ec58cb7fb6f" ;;
      control)     check "$IMAGE" "3a28356c3e544a804bf1025d44075aee71e4947c1eb067c3f0d797c0295be6b5" ;;
      *) echo "unknown variant: $VARIANT (sukisu_only|full|control)" >&2; exit 2 ;;
    esac
    ;;

  *) echo "usage: $0 [configs | artifacts DIR VARIANT | boot IMAGE VARIANT]" >&2; exit 2 ;;
esac

if [ "$fail" -ne 0 ]; then
  echo "$fail check(s) failed"
  exit 1
fi
echo "all checks passed"
