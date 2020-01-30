package com.tekartik.sqflite;

import android.annotation.TargetApi;
import android.database.Cursor;
import android.database.CursorWindow;
import android.database.DatabaseErrorHandler;
import android.database.sqlite.SQLiteCursor;
import android.database.sqlite.SQLiteCursorDriver;
import android.database.sqlite.SQLiteDatabase;
import android.database.sqlite.SQLiteQuery;
import android.os.Build;
import android.util.Log;

import java.io.File;

import static com.tekartik.sqflite.Constant.TAG;

class Database {
    final boolean singleInstance;
    final String path;
    final int id;
    final SQLiteDatabase.CursorFactory cursorFactory;
    final int logLevel;
    SQLiteDatabase sqliteDatabase;
    boolean inTransaction;


    Database(String path, int id, boolean singleInstance, int cursorWindowSize, int logLevel) {
        this.path = path;
        this.singleInstance = singleInstance;
        this.id = id;
        this.cursorFactory = getCursorFactory(cursorWindowSize);
        this.logLevel = logLevel;
    }

    public void open() {
        sqliteDatabase = SQLiteDatabase.openDatabase(path, cursorFactory,
                SQLiteDatabase.CREATE_IF_NECESSARY);
    }

    // Change default error handler to avoid erasing the existing file.
    public void openReadOnly() {
        sqliteDatabase = SQLiteDatabase.openDatabase(path, cursorFactory,
                SQLiteDatabase.OPEN_READONLY, new DatabaseErrorHandler() {
                    @Override
                    public void onCorruption(SQLiteDatabase dbObj) {
                        // ignored
                        // default implementation delete the file
                        //
                        // This happens asynchronously so cannot be tracked. However a simple
                        // access should fail
                    }
                });
    }

    public void close() {
        sqliteDatabase.close();
    }

    public SQLiteDatabase getWritableDatabase() {
        return sqliteDatabase;
    }

    public SQLiteDatabase getReadableDatabase() {
        return sqliteDatabase;
    }

    public boolean enableWriteAheadLogging() {
        try {
            return sqliteDatabase.enableWriteAheadLogging();
        } catch (Exception e) {
            Log.e(TAG, getThreadLogPrefix() + "enable WAL error: " + e);
            return false;
        }
    }

    String getThreadLogTag() {
        Thread thread = Thread.currentThread();

        return "" + id + "," + thread.getName() + "(" + thread.getId() + ")";
    }

    String getThreadLogPrefix() {
        return "[" + getThreadLogTag() + "] ";
    }

    static void deleteDatabase(String path) {
        SQLiteDatabase.deleteDatabase(new File(path));
    }

    static SQLiteDatabase.CursorFactory getCursorFactory(final int cursorWindowSize) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.P || cursorWindowSize <= 0) {
            return null;
        }
        return new CursorFactory(cursorWindowSize);
    }

    @TargetApi(Build.VERSION_CODES.P)
    static class CursorFactory implements SQLiteDatabase.CursorFactory {
        final int cursorWindowSize;

        CursorFactory(int cursorWindowSize) {
            this.cursorWindowSize = cursorWindowSize;
        }
        @Override
        public Cursor newCursor(SQLiteDatabase db, SQLiteCursorDriver masterQuery, String editTable, SQLiteQuery query) {
            SQLiteCursor cursor = new SQLiteCursor(masterQuery, editTable, query);
            cursor.setWindow(new CursorWindow(db.getPath(), cursorWindowSize));
            return cursor;
        }
    }
}
