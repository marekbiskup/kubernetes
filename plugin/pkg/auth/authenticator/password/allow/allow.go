/*
Copyright 2014 The Kubernetes Authors All rights reserved.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/

package allow

import (
	"github.com/GoogleCloudPlatform/kubernetes/pkg/auth/authenticator"
	"github.com/GoogleCloudPlatform/kubernetes/pkg/auth/user"
)

type allowAuthenticator struct{}

// NewAllow returns a password authenticator that allows any non-empty username
func NewAllow() authenticator.Password {
	return allowAuthenticator{}
}

// AuthenticatePassword implements authenticator.Password to allow any non-empty username,
// using the specified username as the name and UID
func (allowAuthenticator) AuthenticatePassword(username, password string) (user.Info, bool, error) {
	if username == "" {
		return nil, false, nil
	}
	return &user.DefaultInfo{Name: username, UID: username}, true, nil
}
