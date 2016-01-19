PROJECT = rabbitmq_federation

DEPS = amqp_client
TEST_DEPS = rabbit

DEP_PLUGINS = rabbit_common/mk/rabbitmq-plugin.mk

# FIXME: Use erlang.mk patched for RabbitMQ, while waiting for PRs to be
# reviewed and merged.

ERLANG_MK_REPO = https://github.com/rabbitmq/erlang.mk.git
ERLANG_MK_COMMIT = rabbitmq-tmp

include rabbitmq-components.mk
include erlang.mk

# --------------------------------------------------------------------
# Testing.
# --------------------------------------------------------------------

FILTER := all
COVER := false

WITH_BROKER_TEST_COMMANDS := \
	rabbit_test_runner:run_in_broker(\"$(CURDIR)/test\",\"$(FILTER)\")
WITH_BROKER_SETUP_SCRIPTS := $(CURDIR)/etc/setup-rabbit-test.sh

TEST_PLUGINS_ROOTDIR := $(TEST_TMPDIR)/plugins

STANDALONE_TEST_COMMANDS := \
	rabbit_test_runner:run_multi(\"$(DEPS_DIR)\",\"$(CURDIR)/test\",\"$(FILTER)\",$(COVER),\"$(TEST_PLUGINS_ROOTDIR)\")

pre-standalone-tests:: test-tmpdir test-dist
	$(verbose) rm -rf $(TEST_PLUGINS_ROOTDIR)
	$(exec_verbose) mkdir -p $(TEST_PLUGINS_ROOTDIR)
	$(verbose) cp -a $(DIST_DIR) $(TEST_PLUGINS_ROOTDIR)
