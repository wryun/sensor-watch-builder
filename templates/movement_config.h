#ifndef MOVEMENT_CONFIG_H_
#define MOVEMENT_CONFIG_H_

#include "movement_faces.h"

const watch_face_t watch_faces[] = {
<% for _, face in pairs(faces) do %>
  <%- face %>,
<% end %>
};

#define MOVEMENT_NUM_FACES (sizeof(watch_faces) / sizeof(watch_face_t))
#define MOVEMENT_SECONDARY_FACE_INDEX <%- secondary_face_index %>

#endif // MOVEMENT_CONFIG_H_
