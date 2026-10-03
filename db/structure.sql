SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: instrument_type; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.instrument_type AS ENUM (
    'bass',
    'brass',
    'drums',
    'guitar',
    'keys',
    'other',
    'strings',
    'vocals',
    'woodwinds'
);


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: alternate_tabs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.alternate_tabs (
    id uuid DEFAULT uuidv7() NOT NULL,
    user_id uuid NOT NULL,
    song_id uuid NOT NULL,
    track_index integer NOT NULL,
    tuning integer[] NOT NULL,
    note_count integer NOT NULL,
    strings jsonb DEFAULT '{}'::jsonb NOT NULL,
    optimizer character varying,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: ar_internal_metadata; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ar_internal_metadata (
    key character varying NOT NULL,
    value character varying,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: credentials; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.credentials (
    id bigint NOT NULL,
    user_id uuid NOT NULL,
    provider character varying NOT NULL,
    uid character varying NOT NULL,
    token jsonb,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: credentials_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.credentials_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: credentials_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.credentials_id_seq OWNED BY public.credentials.id;


--
-- Name: friendly_id_slugs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.friendly_id_slugs (
    id uuid DEFAULT uuidv7() NOT NULL,
    slug character varying NOT NULL,
    sluggable_type character varying NOT NULL,
    sluggable_id uuid NOT NULL,
    scope character varying,
    created_at timestamp(6) without time zone
);


--
-- Name: play_histories; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.play_histories (
    id bigint NOT NULL,
    user_id uuid NOT NULL,
    song_id uuid NOT NULL,
    date date NOT NULL,
    duration double precision DEFAULT 0.0 NOT NULL
);


--
-- Name: play_histories_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.play_histories_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: play_histories_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.play_histories_id_seq OWNED BY public.play_histories.id;


--
-- Name: playlists; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.playlists (
    id uuid DEFAULT uuidv7() NOT NULL,
    user_id uuid NOT NULL,
    name character varying NOT NULL,
    song_ids uuid[] DEFAULT '{}'::uuid[] NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: schema_migrations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.schema_migrations (
    version character varying NOT NULL
);


--
-- Name: solid_cable_messages; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.solid_cable_messages (
    id bigint NOT NULL,
    channel bytea NOT NULL,
    payload bytea NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    channel_hash bigint NOT NULL
);


--
-- Name: solid_cable_messages_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.solid_cable_messages_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: solid_cable_messages_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.solid_cable_messages_id_seq OWNED BY public.solid_cable_messages.id;


--
-- Name: song_notes; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.song_notes (
    id uuid DEFAULT uuidv7() NOT NULL,
    user_id uuid NOT NULL,
    song_id uuid NOT NULL,
    speed double precision,
    looping boolean,
    count_in boolean,
    metronome boolean,
    range_start_tick integer,
    range_end_tick integer,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    volume integer,
    tracks integer[],
    muted_tracks integer[],
    solo_tracks integer[],
    track_volumes jsonb,
    track_tunings jsonb
);


--
-- Name: songs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.songs (
    id uuid DEFAULT uuidv7() NOT NULL,
    title character varying NOT NULL,
    artist character varying,
    slug character varying,
    tempo integer,
    track_types public.instrument_type[] DEFAULT '{}'::public.instrument_type[] NOT NULL,
    score_data jsonb NOT NULL,
    audio_data jsonb,
    cover_data jsonb,
    sync_points jsonb,
    jellyfin_id character varying,
    songsterr_id integer,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    genres character varying[] DEFAULT '{}'::character varying[] NOT NULL
);


--
-- Name: songsterr_songs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.songsterr_songs (
    id integer NOT NULL,
    song_id uuid NOT NULL,
    revision_id integer,
    data jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: users; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.users (
    id uuid DEFAULT uuidv7() NOT NULL,
    name character varying,
    email character varying NOT NULL,
    instrument_types public.instrument_type[] DEFAULT '{}'::public.instrument_type[] NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: credentials id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.credentials ALTER COLUMN id SET DEFAULT nextval('public.credentials_id_seq'::regclass);


--
-- Name: play_histories id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.play_histories ALTER COLUMN id SET DEFAULT nextval('public.play_histories_id_seq'::regclass);


--
-- Name: solid_cable_messages id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.solid_cable_messages ALTER COLUMN id SET DEFAULT nextval('public.solid_cable_messages_id_seq'::regclass);


--
-- Name: alternate_tabs alternate_tabs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.alternate_tabs
    ADD CONSTRAINT alternate_tabs_pkey PRIMARY KEY (id);


--
-- Name: ar_internal_metadata ar_internal_metadata_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ar_internal_metadata
    ADD CONSTRAINT ar_internal_metadata_pkey PRIMARY KEY (key);


--
-- Name: credentials credentials_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.credentials
    ADD CONSTRAINT credentials_pkey PRIMARY KEY (id);


--
-- Name: friendly_id_slugs friendly_id_slugs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.friendly_id_slugs
    ADD CONSTRAINT friendly_id_slugs_pkey PRIMARY KEY (id);


--
-- Name: play_histories play_histories_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.play_histories
    ADD CONSTRAINT play_histories_pkey PRIMARY KEY (id);


--
-- Name: playlists playlists_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.playlists
    ADD CONSTRAINT playlists_pkey PRIMARY KEY (id);


--
-- Name: schema_migrations schema_migrations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.schema_migrations
    ADD CONSTRAINT schema_migrations_pkey PRIMARY KEY (version);


--
-- Name: solid_cable_messages solid_cable_messages_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.solid_cable_messages
    ADD CONSTRAINT solid_cable_messages_pkey PRIMARY KEY (id);


--
-- Name: song_notes song_notes_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.song_notes
    ADD CONSTRAINT song_notes_pkey PRIMARY KEY (id);


--
-- Name: songs songs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.songs
    ADD CONSTRAINT songs_pkey PRIMARY KEY (id);


--
-- Name: songsterr_songs songsterr_songs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.songsterr_songs
    ADD CONSTRAINT songsterr_songs_pkey PRIMARY KEY (id);


--
-- Name: users users_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_pkey PRIMARY KEY (id);


--
-- Name: idx_on_user_id_song_id_track_index_tuning_ec0880e794; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_on_user_id_song_id_track_index_tuning_ec0880e794 ON public.alternate_tabs USING btree (user_id, song_id, track_index, tuning);


--
-- Name: index_alternate_tabs_on_song_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_alternate_tabs_on_song_id ON public.alternate_tabs USING btree (song_id);


--
-- Name: index_credentials_on_provider_and_uid; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_credentials_on_provider_and_uid ON public.credentials USING btree (provider, uid);


--
-- Name: index_credentials_on_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_credentials_on_user_id ON public.credentials USING btree (user_id);


--
-- Name: index_friendly_id_slugs_on_slug_and_sluggable_type_and_scope; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_friendly_id_slugs_on_slug_and_sluggable_type_and_scope ON public.friendly_id_slugs USING btree (slug, sluggable_type, scope) NULLS NOT DISTINCT;


--
-- Name: index_friendly_id_slugs_on_sluggable; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_friendly_id_slugs_on_sluggable ON public.friendly_id_slugs USING btree (sluggable_type, sluggable_id);


--
-- Name: index_play_histories_on_song_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_play_histories_on_song_id ON public.play_histories USING btree (song_id);


--
-- Name: index_play_histories_on_user_id_and_song_id_and_date; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_play_histories_on_user_id_and_song_id_and_date ON public.play_histories USING btree (user_id, song_id, date);


--
-- Name: index_playlists_on_user_id_and_name; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_playlists_on_user_id_and_name ON public.playlists USING btree (user_id, name);


--
-- Name: index_solid_cable_messages_on_channel_hash; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_solid_cable_messages_on_channel_hash ON public.solid_cable_messages USING btree (channel_hash);


--
-- Name: index_solid_cable_messages_on_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_solid_cable_messages_on_created_at ON public.solid_cable_messages USING btree (created_at);


--
-- Name: index_song_notes_on_song_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_song_notes_on_song_id ON public.song_notes USING btree (song_id);


--
-- Name: index_song_notes_on_user_id_and_song_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_song_notes_on_user_id_and_song_id ON public.song_notes USING btree (user_id, song_id);


--
-- Name: index_songs_on_artist_and_title; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_songs_on_artist_and_title ON public.songs USING btree (artist, title);


--
-- Name: index_songs_on_jellyfin_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_songs_on_jellyfin_id ON public.songs USING btree (jellyfin_id);


--
-- Name: index_songs_on_slug; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_songs_on_slug ON public.songs USING btree (slug);


--
-- Name: index_songs_on_songsterr_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_songs_on_songsterr_id ON public.songs USING btree (songsterr_id);


--
-- Name: index_songs_on_track_types; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_songs_on_track_types ON public.songs USING gin (track_types);


--
-- Name: index_songsterr_songs_on_song_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_songsterr_songs_on_song_id ON public.songsterr_songs USING btree (song_id);


--
-- Name: index_users_on_email; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_users_on_email ON public.users USING btree (email);


--
-- Name: play_histories fk_rails_325b78ed95; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.play_histories
    ADD CONSTRAINT fk_rails_325b78ed95 FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: credentials fk_rails_32938455c2; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.credentials
    ADD CONSTRAINT fk_rails_32938455c2 FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: songsterr_songs fk_rails_33c93acee3; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.songsterr_songs
    ADD CONSTRAINT fk_rails_33c93acee3 FOREIGN KEY (song_id) REFERENCES public.songs(id) ON DELETE CASCADE;


--
-- Name: song_notes fk_rails_740efb49a0; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.song_notes
    ADD CONSTRAINT fk_rails_740efb49a0 FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: song_notes fk_rails_8deb7ab4b7; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.song_notes
    ADD CONSTRAINT fk_rails_8deb7ab4b7 FOREIGN KEY (song_id) REFERENCES public.songs(id) ON DELETE CASCADE;


--
-- Name: play_histories fk_rails_a6647c9882; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.play_histories
    ADD CONSTRAINT fk_rails_a6647c9882 FOREIGN KEY (song_id) REFERENCES public.songs(id) ON DELETE CASCADE;


--
-- Name: alternate_tabs fk_rails_cf2ed07d2d; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.alternate_tabs
    ADD CONSTRAINT fk_rails_cf2ed07d2d FOREIGN KEY (song_id) REFERENCES public.songs(id) ON DELETE CASCADE;


--
-- Name: playlists fk_rails_d67ef1eb45; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.playlists
    ADD CONSTRAINT fk_rails_d67ef1eb45 FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: alternate_tabs fk_rails_e8ce48a749; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.alternate_tabs
    ADD CONSTRAINT fk_rails_e8ce48a749 FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- PostgreSQL database dump complete
--

SET search_path TO "$user", public;

INSERT INTO "schema_migrations" (version) VALUES
('20261003000000'),
('20261002000001'),
('20261002000000'),
('20261001000000'),
('20260930120000'),
('20260930000000'),
('20260928000000'),
('20260927071000');

