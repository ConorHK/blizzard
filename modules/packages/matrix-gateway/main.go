package main

import (
	"context"
	"errors"
	"fmt"
	"log/slog"
	"os"
	"os/signal"
	"strings"
	"sync"
	"syscall"
	"time"

	_ "github.com/mattn/go-sqlite3"
	"maunium.net/go/mautrix"
	"maunium.net/go/mautrix/crypto/cryptohelper"
	"maunium.net/go/mautrix/event"
	"maunium.net/go/mautrix/format"
	"maunium.net/go/mautrix/id"
)

const askTimeout = 5 * time.Minute

type prompt struct {
	room id.RoomID
	text string
}

func mustEnv(key string) string {
	value := os.Getenv(key)
	if value == "" {
		slog.Error("missing environment variable", "key", key)
		os.Exit(1)
	}
	return value
}

func fatal(msg string, err error) {
	slog.Error(msg, "err", err)
	os.Exit(1)
}

func main() {
	homeserver := mustEnv("MATRIX_HOMESERVER")
	user := mustEnv("MATRIX_USER")
	admin := id.UserID(mustEnv("MATRIX_ADMIN"))
	password := mustEnv("MATRIX_PASSWORD")
	pickleKey := mustEnv("MATRIX_PICKLE_KEY")
	database := mustEnv("MATRIX_DATABASE")
	socket := mustEnv("MATRIX_GATEWAY_SOCKET")
	agentCommand := mustEnv("MATRIX_AGENT_COMMAND")
	workerCommand := mustEnv("MATRIX_WORKER_COMMAND")
	rulesSocket := mustEnv("MATRIX_RULES_SOCKET")
	rulesFile := mustEnv("MATRIX_RULES_FILE")
	llmURL := mustEnv("MATRIX_LLM_URL")
	llmModel := mustEnv("MATRIX_LLM_MODEL")

	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()

	buf := newBuffer(500)
	store, err := loadRules(rulesFile)
	if err != nil {
		fatal("load rules", err)
	}
	assistant, err := startAgent(ctx, agentCommand)
	if err != nil {
		fatal("start agent", err)
	}
	worker, err := startAgent(ctx, workerCommand, "MATRIX_RULES_SOCKET")
	if err != nil {
		fatal("start worker", err)
	}

	client, err := mautrix.NewClient(homeserver, "", "")
	if err != nil {
		fatal("create client", err)
	}
	// Joining many portals at once trips Synapse rate limits, so honour Retry-After.
	client.DefaultHTTPRetries = 5

	helper, err := cryptohelper.NewCryptoHelper(client, []byte(pickleKey), database)
	if err != nil {
		fatal("create crypto helper", err)
	}
	helper.LoginAs = &mautrix.ReqLogin{
		Type:                     mautrix.AuthTypePassword,
		Identifier:               mautrix.UserIdentifier{Type: mautrix.IdentifierTypeUser, User: user},
		Password:                 password,
		InitialDeviceDisplayName: "matrix-gateway",
	}
	if err := helper.Init(ctx); err != nil {
		fatal("init crypto", err)
	}
	client.Crypto = helper

	known := newRooms(client, admin)
	if err := listenUnix(ctx, socket, chatHandler(buf, known)); err != nil {
		fatal("start chat api", err)
	}
	if err := listenUnix(ctx, rulesSocket, rulesHandler(store)); err != nil {
		fatal("start rules api", err)
	}
	engine := newRuleEngine(store, worker, llmURL, llmModel, func(ctx context.Context, text string) (id.EventID, error) {
		roomID, ok := known.controlRoom(ctx)
		if !ok {
			return "", errors.New("no control room")
		}
		content := format.RenderMarkdown(text, true, false)
		resp, err := client.SendMessageEvent(ctx, roomID, event.EventMessage, &content)
		if err != nil {
			return "", err
		}
		return resp.EventID, nil
	})
	go engine.run(ctx)
	prompts := make(chan prompt, 16)
	go answer(ctx, client, assistant, prompts)

	syncer := client.Syncer.(*mautrix.DefaultSyncer)
	acceptInvite := func(ctx context.Context, roomID id.RoomID, sender id.UserID) {
		// Bridge relay mode lets outside users invite, so only the admin may add rooms.
		if sender != admin {
			slog.Warn("ignored invite", "room", roomID, "sender", sender)
			return
		}
		if _, err := client.JoinRoomByID(ctx, roomID); err != nil {
			slog.Error("join room", "room", roomID, "err", err)
			return
		}
		slog.Info("joined room", "room", roomID)
	}
	syncer.OnEventType(event.StateMember, func(ctx context.Context, evt *event.Event) {
		known.forget(evt.RoomID)
		if evt.GetStateKey() == client.UserID.String() && evt.Content.AsMember().Membership == event.MembershipInvite {
			go acceptInvite(ctx, evt.RoomID, evt.Sender)
		}
	})
	remember := func(ctx context.Context, evt *event.Event) (record, bool) {
		msg := evt.Content.AsMessage()
		if evt.Sender == client.UserID || msg.MsgType == event.MsgNotice {
			return record{}, false
		}
		body := msg.Body
		if msg.MsgType != event.MsgText && msg.MsgType != event.MsgEmote {
			body = "[" + strings.TrimPrefix(string(msg.MsgType), "m.") + "] " + body
		}
		rec := record{
			ID:     evt.ID.String(),
			Time:   time.UnixMilli(evt.Timestamp),
			Chat:   known.name(ctx, evt.RoomID),
			Sender: known.sender(ctx, evt.RoomID, evt.Sender),
			Body:   body,
		}
		buf.add(rec)
		return rec, true
	}
	// Room keys for messages sent while offline arrive in the first sync, so backfill must wait for it.
	var backfillOnce sync.Once
	syncer.OnSync(func(ctx context.Context, resp *mautrix.RespSync, _ string) bool {
		backfillOnce.Do(func() {
			// The first sync is skipped below, so accept invites that arrived while offline here.
			for roomID, room := range resp.Rooms.Invite {
				for _, evt := range room.State.Events {
					if evt.Type != event.StateMember || evt.GetStateKey() != client.UserID.String() {
						continue
					}
					_ = evt.Content.ParseRaw(event.StateMember)
					if evt.Content.AsMember().Membership == event.MembershipInvite {
						go acceptInvite(ctx, roomID, evt.Sender)
					}
				}
			}
			go backfill(ctx, client, helper, known, 50, remember)
		})
		return true
	})
	syncer.OnSync(client.DontProcessOldEvents)
	syncer.OnEventType(event.EventMessage, func(ctx context.Context, evt *event.Event) {
		if evt.Sender == client.UserID {
			return
		}
		if evt.Sender == admin && known.isControl(ctx, evt.RoomID) {
			select {
			case prompts <- prompt{room: evt.RoomID, text: dmText(evt, engine, store)}:
			default:
				slog.Warn("prompt queue full", "room", evt.RoomID)
			}
			return
		}
		// Only live messages trigger rules, so a restart never replays old matches.
		if rec, ok := remember(ctx, evt); ok && evt.Sender != admin {
			engine.submit(rec)
		}
		slog.Info("message", "room", evt.RoomID, "length", len(evt.Content.AsMessage().Body))
	})

	slog.Info("syncing", "user", client.UserID, "device", client.DeviceID)
	err = client.SyncWithContext(ctx)
	if closeErr := helper.Close(); closeErr != nil {
		slog.Error("close crypto", "err", closeErr)
	}
	if err != nil && !errors.Is(err, context.Canceled) {
		fatal("sync", err)
	}
}

// answer runs prompts one at a time so a slow model never blocks the sync loop.
func answer(ctx context.Context, client *mautrix.Client, assistant *agent, prompts <-chan prompt) {
	for {
		select {
		case <-ctx.Done():
			return
		case p := <-prompts:
			reply := respond(ctx, client, assistant, p)
			content := format.RenderMarkdown(reply, true, false)
			if _, err := client.SendMessageEvent(ctx, p.room, event.EventMessage, &content); err != nil {
				slog.Error("send reply", "room", p.room, "err", err)
			}
		}
	}
}

func respond(ctx context.Context, client *mautrix.Client, assistant *agent, p prompt) string {
	if strings.TrimSpace(p.text) == "!reset" {
		if err := assistant.reset(ctx); err != nil {
			slog.Error("reset agent", "err", err)
			return "Reset failed."
		}
		return "Started a new conversation."
	}

	_, _ = client.UserTyping(ctx, p.room, true, askTimeout)
	defer func() { _, _ = client.UserTyping(ctx, p.room, false, 0) }()

	askCtx, cancel := context.WithTimeout(ctx, askTimeout)
	defer cancel()
	stamped := "[now: " + time.Now().Format("Mon 2006-01-02 15:04") + "]\n" + p.text
	reply, err := assistant.ask(askCtx, stamped)
	if err != nil {
		slog.Error("ask agent", "err", err)
		return "The assistant failed to answer."
	}
	return reply
}

// dmText turns a reply to a rule result into feedback the assistant can act on.
func dmText(evt *event.Event, engine *ruleEngine, store *ruleStore) string {
	msg := evt.Content.AsMessage()
	replyTo := msg.RelatesTo.GetReplyTo()
	if replyTo == "" {
		return msg.Body
	}
	msg.RemoveReplyFallback()
	res, ok := engine.resultFor(replyTo)
	if !ok {
		return msg.Body
	}
	if err := store.addFeedback(res.RuleID, msg.Body); err != nil {
		slog.Error("record feedback", "rule", res.RuleID, "err", err)
	}
	return fmt.Sprintf("[feedback on rule %s %q, which said: %s]\n%s", res.RuleID, res.Name, res.Text, msg.Body)
}
