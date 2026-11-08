package main

import (
	"context"
	"errors"
	"log/slog"
	"os"
	"os/signal"
	"syscall"

	_ "github.com/mattn/go-sqlite3"
	"maunium.net/go/mautrix"
	"maunium.net/go/mautrix/crypto/cryptohelper"
	"maunium.net/go/mautrix/event"
	"maunium.net/go/mautrix/id"
)

func mustEnv(key string) string {
	value := os.Getenv(key)
	if value == "" {
		slog.Error("missing environment variable", "key", key)
		os.Exit(1)
	}
	return value
}

func main() {
	homeserver := mustEnv("MATRIX_HOMESERVER")
	user := mustEnv("MATRIX_USER")
	admin := id.UserID(mustEnv("MATRIX_ADMIN"))
	password := mustEnv("MATRIX_PASSWORD")
	pickleKey := mustEnv("MATRIX_PICKLE_KEY")
	database := mustEnv("MATRIX_DATABASE")

	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()

	client, err := mautrix.NewClient(homeserver, "", "")
	if err != nil {
		slog.Error("create client", "err", err)
		os.Exit(1)
	}

	helper, err := cryptohelper.NewCryptoHelper(client, []byte(pickleKey), database)
	if err != nil {
		slog.Error("create crypto helper", "err", err)
		os.Exit(1)
	}
	helper.LoginAs = &mautrix.ReqLogin{
		Type:                     mautrix.AuthTypePassword,
		Identifier:               mautrix.UserIdentifier{Type: mautrix.IdentifierTypeUser, User: user},
		Password:                 password,
		InitialDeviceDisplayName: "matrix-gateway",
	}
	if err := helper.Init(ctx); err != nil {
		slog.Error("init crypto", "err", err)
		os.Exit(1)
	}
	client.Crypto = helper

	syncer := client.Syncer.(*mautrix.DefaultSyncer)
	syncer.OnSync(client.DontProcessOldEvents)
	syncer.OnEventType(event.StateMember, func(ctx context.Context, evt *event.Event) {
		if evt.GetStateKey() != client.UserID.String() || evt.Content.AsMember().Membership != event.MembershipInvite {
			return
		}
		// Bridge relay mode lets outside users invite, so only the admin may add rooms.
		if evt.Sender != admin {
			slog.Warn("ignored invite", "room", evt.RoomID, "sender", evt.Sender)
			return
		}
		if _, err := client.JoinRoomByID(ctx, evt.RoomID); err != nil {
			slog.Error("join room", "room", evt.RoomID, "err", err)
			return
		}
		slog.Info("joined room", "room", evt.RoomID)
	})
	syncer.OnEventType(event.EventMessage, func(_ context.Context, evt *event.Event) {
		if evt.Sender == client.UserID {
			return
		}
		msg := evt.Content.AsMessage()
		slog.Info("message", "room", evt.RoomID, "sender", evt.Sender, "type", msg.MsgType, "length", len(msg.Body))
	})

	slog.Info("syncing", "user", client.UserID, "device", client.DeviceID)
	err = client.SyncWithContext(ctx)
	if closeErr := helper.Close(); closeErr != nil {
		slog.Error("close crypto", "err", closeErr)
	}
	if err != nil && !errors.Is(err, context.Canceled) {
		slog.Error("sync", "err", err)
		os.Exit(1)
	}
}
