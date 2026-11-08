package main

import (
	"context"
	"errors"
	"log/slog"
	"sort"

	"maunium.net/go/mautrix"
	"maunium.net/go/mautrix/crypto/cryptohelper"
	"maunium.net/go/mautrix/event"
)

// backfill reloads recent history from the homeserver, since the buffer starts empty after every restart.
func backfill(ctx context.Context, client *mautrix.Client, helper *cryptohelper.CryptoHelper, known *rooms, perRoom int, remember func(context.Context, *event.Event) (record, bool)) {
	joined, err := client.JoinedRooms(ctx)
	if err != nil {
		slog.Error("list joined rooms", "err", err)
		return
	}
	var events []*event.Event
	for _, roomID := range joined.JoinedRooms {
		if known.isControl(ctx, roomID) {
			continue
		}
		resp, err := client.Messages(ctx, roomID, "", "", mautrix.DirectionBackward, nil, perRoom)
		if err != nil {
			slog.Error("fetch history", "room", roomID, "err", err)
			continue
		}
		for _, evt := range resp.Chunk {
			evt.RoomID = roomID
			if evt.Type != event.EventEncrypted && evt.Type != event.EventMessage {
				continue
			}
			evt.Type.Class = event.MessageEventType
			if err := evt.Content.ParseRaw(evt.Type); err != nil && !errors.Is(err, event.ErrContentAlreadyParsed) {
				continue
			}
			if evt.Type == event.EventEncrypted {
				decrypted, err := helper.Decrypt(ctx, evt)
				if err != nil {
					continue
				}
				evt = decrypted
			}
			if evt.Type == event.EventMessage {
				events = append(events, evt)
			}
		}
	}
	sort.Slice(events, func(i, j int) bool { return events[i].Timestamp < events[j].Timestamp })
	for _, evt := range events {
		remember(ctx, evt)
	}
	slog.Info("backfilled", "rooms", len(joined.JoinedRooms), "messages", len(events))
}
