package main

import (
	"context"
	"sync"

	"maunium.net/go/mautrix"
	"maunium.net/go/mautrix/event"
	"maunium.net/go/mautrix/id"
)

// rooms caches room names and member display names, dropping a room's entry when its membership changes.
type rooms struct {
	client  *mautrix.Client
	admin   id.UserID
	mu      sync.Mutex
	names   map[id.RoomID]string
	members map[id.RoomID]map[id.UserID]string
}

func newRooms(client *mautrix.Client, admin id.UserID) *rooms {
	return &rooms{
		client:  client,
		admin:   admin,
		names:   map[id.RoomID]string{},
		members: map[id.RoomID]map[id.UserID]string{},
	}
}

func (r *rooms) forget(roomID id.RoomID) {
	r.mu.Lock()
	defer r.mu.Unlock()
	delete(r.names, roomID)
	delete(r.members, roomID)
}

func (r *rooms) memberNames(ctx context.Context, roomID id.RoomID) map[id.UserID]string {
	r.mu.Lock()
	cached, ok := r.members[roomID]
	r.mu.Unlock()
	if ok {
		return cached
	}
	resp, err := r.client.JoinedMembers(ctx, roomID)
	if err != nil {
		return nil
	}
	names := make(map[id.UserID]string, len(resp.Joined))
	for userID, member := range resp.Joined {
		names[userID] = member.DisplayName
	}
	r.mu.Lock()
	r.members[roomID] = names
	r.mu.Unlock()
	return names
}

func (r *rooms) sender(ctx context.Context, roomID id.RoomID, userID id.UserID) string {
	if name := r.memberNames(ctx, roomID)[userID]; name != "" {
		return name
	}
	return userID.String()
}

func (r *rooms) name(ctx context.Context, roomID id.RoomID) string {
	r.mu.Lock()
	name, ok := r.names[roomID]
	r.mu.Unlock()
	if ok {
		return name
	}
	var content event.RoomNameEventContent
	if err := r.client.StateEvent(ctx, roomID, event.StateRoomName, "", &content); err != nil || content.Name == "" {
		name = roomID.String()
	} else {
		name = content.Name
	}
	r.mu.Lock()
	r.names[roomID] = name
	r.mu.Unlock()
	return name
}

// isControl reports a private room holding only the admin and this bot.
func (r *rooms) isControl(ctx context.Context, roomID id.RoomID) bool {
	members := r.memberNames(ctx, roomID)
	_, hasAdmin := members[r.admin]
	_, hasBot := members[r.client.UserID]
	return len(members) == 2 && hasAdmin && hasBot
}

// portals names every joined room except the admin's control room.
func (r *rooms) portals(ctx context.Context) []string {
	joined, err := r.client.JoinedRooms(ctx)
	if err != nil {
		return nil
	}
	var names []string
	for _, roomID := range joined.JoinedRooms {
		if !r.isControl(ctx, roomID) {
			names = append(names, r.name(ctx, roomID))
		}
	}
	return names
}

// controlRoom finds the admin's private room with this bot, where rule results go.
func (r *rooms) controlRoom(ctx context.Context) (id.RoomID, bool) {
	joined, err := r.client.JoinedRooms(ctx)
	if err != nil {
		return "", false
	}
	for _, roomID := range joined.JoinedRooms {
		if r.isControl(ctx, roomID) {
			return roomID, true
		}
	}
	return "", false
}
