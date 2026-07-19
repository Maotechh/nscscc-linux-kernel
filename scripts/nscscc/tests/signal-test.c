// SPDX-License-Identifier: GPL-2.0

#define _GNU_SOURCE

#include <errno.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/time.h>
#include <unistd.h>

static volatile sig_atomic_t handled_signal;

static void handle_signal(int signal_number)
{
	static const char message[] = "HANDLER_ENTERED\n";

	handled_signal = signal_number;
	write(STDOUT_FILENO, message, sizeof(message) - 1);
}

static void print_action(const char *label, const struct sigaction *action)
{
	printf("%s handler=%p flags=0x%lx restorer=%p\n",
	       label,
	       (void *)action->sa_handler,
	       (unsigned long)action->sa_flags,
	       (void *)action->sa_restorer);
}

int main(int argc, char **argv)
{
	struct sigaction action;
	struct sigaction current;
	struct itimerval timer;
	int result;

	setvbuf(stdout, NULL, _IONBF, 0);
	memset(&action, 0, sizeof(action));
	memset(&current, 0, sizeof(current));
	action.sa_handler = handle_signal;
	sigemptyset(&action.sa_mask);

	errno = 0;
	result = sigaction(SIGALRM, &action, NULL);
	printf("sigaction_set result=%d errno=%d (%s)\n",
	       result, errno, strerror(errno));
	if (result != 0)
		return 10;

	errno = 0;
	result = sigaction(SIGALRM, NULL, &current);
	printf("sigaction_get result=%d errno=%d (%s)\n",
	       result, errno, strerror(errno));
	if (result != 0)
		return 11;
	print_action("sigaction_current", &current);

	if (argc > 1 && strcmp(argv[1], "timer") == 0) {
		memset(&timer, 0, sizeof(timer));
		timer.it_value.tv_usec = 200000;
		errno = 0;
		result = setitimer(ITIMER_REAL, &timer, NULL);
		printf("setitimer result=%d errno=%d (%s)\n",
		       result, errno, strerror(errno));
		if (result != 0)
			return 12;
		printf("waiting_for_timer\n");
		pause();
	} else {
		printf("sending_sigalrm pid=%ld\n", (long)getpid());
		kill(getpid(), SIGALRM);
	}

	printf("AFTER_HANDLER handled_signal=%d\n", handled_signal);
	return handled_signal == SIGALRM ? 0 : 13;
}
