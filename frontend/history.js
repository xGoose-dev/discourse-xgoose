const DB = "xgoose-local-history-v1";
function database() {
  return new Promise((resolve, reject) => {
    const request = indexedDB.open(DB, 1);
    request.onupgradeneeded = () => {
      for (const name of ["entries", "chats"]) {
        const store = request.result.createObjectStore(name, {
          keyPath: "key",
        });
        store.createIndex("owner", "owner");
      }
    };
    request.onsuccess = () => resolve(request.result);
    request.onerror = () => reject(request.error);
  });
}
export function historyStore(owner) {
  const key = (id) => `${owner}:${id}`;
  async function transaction(mode, operation) {
    const db = await database();
    try {
      return await new Promise((resolve, reject) => {
        const tx = db.transaction(["entries", "chats"], mode);
        let value;
        operation(tx, (result) => {
          value = result;
        });
        tx.oncomplete = () => resolve(value);
        tx.onerror = () => reject(tx.error);
        tx.onabort = () => reject(tx.error || new Error("storage_failed"));
      });
    } finally {
      db.close();
    }
  }
  return {
    save(chat) {
      return transaction("readwrite", (tx) => {
        const record = { ...chat, owner, key: key(chat.id) };
        tx.objectStore("chats").put(record);
        tx.objectStore("entries").put({
          key: record.key,
          owner,
          id: chat.id,
          title: chat.title,
          createdAt: chat.createdAt,
          updatedAt: chat.updatedAt,
          costUsd: chat.costUsd || 0,
          imageCount: chat.imageCount || 0,
        });
      });
    },
    list() {
      return transaction("readonly", (tx, done) => {
        const request = tx.objectStore("entries").index("owner").getAll(owner);
        request.onsuccess = () =>
          done(request.result.sort((a, b) => b.updatedAt - a.updatedAt));
      });
    },
    get(id) {
      return transaction("readonly", (tx, done) => {
        const request = tx.objectStore("chats").get(key(id));
        request.onsuccess = () =>
          done(request.result?.owner === owner ? request.result : null);
      });
    },
    delete(id) {
      return transaction("readwrite", (tx) => {
        tx.objectStore("entries").delete(key(id));
        tx.objectStore("chats").delete(key(id));
      });
    },
  };
}
