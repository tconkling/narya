#include "presents/stable.h"
#include "ClientObject.h"

using namespace presents::data;

DEFINE_STREAMABLE("com.threerings.presents.data.ClientObject", ClientObject);

void ClientObject::readObject (ObjectInputStream& in)
{
    presents::dobj::DObject::readObject(in);
    username = boost::static_pointer_cast<util::Name>(in.readObject());
    receivers = boost::static_pointer_cast<presents::dobj::DSet>(in.readObject());
}

void ClientObject::writeObject (ObjectOutputStream& out) const
{
    presents::dobj::DObject::writeObject(out);
    out.writeObject(username);
    out.writeObject(receivers);
}
