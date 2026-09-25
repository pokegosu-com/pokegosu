package hooks

import (
	"bytes"
	"encoding/json"
	"fmt"
)

// object is a JSON object that keeps its keys in the order they were read.
//
// Hooks are written into a settings file that belongs to somebody else's
// program and to the person who edits it by hand. Decoding it into a map
// would write it back with every key sorted, so the one change made here
// would come with a diff over the whole file.
type object []member

type member struct {
	Key   string
	Value json.RawMessage
}

func (o *object) UnmarshalJSON(data []byte) error {
	dec := json.NewDecoder(bytes.NewReader(data))
	if tok, err := dec.Token(); err != nil || tok != json.Delim('{') {
		return fmt.Errorf("not a JSON object")
	}

	*o = (*o)[:0]
	for dec.More() {
		tok, err := dec.Token()
		if err != nil {
			return err
		}
		var value json.RawMessage
		if err := dec.Decode(&value); err != nil {
			return err
		}
		*o = append(*o, member{Key: tok.(string), Value: value})
	}
	_, err := dec.Token()
	return err
}

func (o object) MarshalJSON() ([]byte, error) {
	var buf bytes.Buffer
	buf.WriteByte('{')
	for i, m := range o {
		if i > 0 {
			buf.WriteByte(',')
		}
		key, err := marshal(m.Key)
		if err != nil {
			return nil, err
		}
		buf.Write(key)
		buf.WriteByte(':')
		buf.Write(m.Value)
	}
	buf.WriteByte('}')
	return buf.Bytes(), nil
}

// get returns the value under key, or nil.
func (o object) get(key string) json.RawMessage {
	for _, m := range o {
		if m.Key == key {
			return m.Value
		}
	}
	return nil
}

// set replaces the value under key where it stands, or appends it.
func (o *object) set(key string, value json.RawMessage) {
	for i, m := range *o {
		if m.Key == key {
			(*o)[i].Value = value
			return
		}
	}
	*o = append(*o, member{Key: key, Value: value})
}

// remove drops key, if it is there.
func (o *object) remove(key string) {
	for i, m := range *o {
		if m.Key == key {
			*o = append((*o)[:i], (*o)[i+1:]...)
			return
		}
	}
}

// marshal is json.Marshal without HTML escaping. The settings are read by
// people and by a shell, not by a browser, and a hook's `>>` escaped as
// \u003e\u003e is correct but unreadable. It also keeps a person's own values
// as they wrote them, since RawMessage is escaped on the way out too.
func marshal(v any) ([]byte, error) {
	var buf bytes.Buffer
	enc := json.NewEncoder(&buf)
	enc.SetEscapeHTML(false)
	if err := enc.Encode(v); err != nil {
		return nil, err
	}
	return bytes.TrimSuffix(buf.Bytes(), []byte("\n")), nil
}
