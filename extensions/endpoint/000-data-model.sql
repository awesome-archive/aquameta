/******************************************************************************
 * ENDPOINT SERVER
 * HTTP request handler for a datum REST interface
 * HTTP arbitrary resource server
 ******************************************************************************/

create schema endpoint2;
set search_path=endpoint2;



/******************************************************************************
 * endpoint.mimetype
 * A big table containing all the mimetypes
 ******************************************************************************/
create table mimetype (
    id uuid not null default public.uuid_generate_v4() primary key,
    mimetype text not null unique
);

/******************************************************************************
 * endpoint.mimetype_extension
 * The filename extensions associated with a particular mimetype.  Unused?
 ******************************************************************************/
create table mimetype_extension (
    id uuid not null default public.uuid_generate_v4() primary key,
    mimetype_id uuid not null references endpoint2.mimetype(id),
    extension text unique
);

/******************************************************************************
 * endpoint.column_mimetype
 * Describes a particular database column's mimetype, which is used in the
 * field_select() function, which serves the raw content of a particular field.
 ******************************************************************************/
create table column_mimetype(
    id uuid not null default public.uuid_generate_v4() primary key,
    column_id meta2.column_id not null,
    mimetype_id uuid not null references endpoint2.mimetype(id)
);




/******************************************************************************
 * endpoint.resource
 * These tables contain static resources that exist at a URL path, to be served
 * by the endpoint upon a GET request matching their path.
 ******************************************************************************/

create table endpoint2."resource_binary" (
    id uuid not null default public.uuid_generate_v4() primary key,
    path text not null,
    mimetype_id uuid not null references endpoint2.mimetype(id) on delete restrict on update cascade,
    active boolean default true,
    content bytea not null
);

create table endpoint2.resource (
    id uuid not null default public.uuid_generate_v4() primary key,
    path text not null,
    mimetype_id uuid not null references mimetype(id) on delete restrict on update cascade,
    active boolean default true,
    content text not null default ''
);



/******************************************************************************
 * endpoint.resource_function
 *
 * Returns the result of a function call as a resource. Functions must return
 * one row with one column, the content to be served.  Mimetype is specified by
 * the resource_function.mimetype_id column.
 *
 * Nice to have:  Multi-mimetype functions??  Functions must return one row
 * with one or two columns.  When it returns two columns, one must be named
 * "mimetype", which sets the resource's content-type, and takes precedence
 * over the value of mimetype_id.
 * 
 * Question: functions that return binary data??  totally possible...
  FIXME: Do we handle these here, or in the Go request handler?  Pick a damn pattern.
 ******************************************************************************/

create table endpoint2.resource_function (
    id uuid not null default public.uuid_generate_v4() primary key,
    function_id meta2.function_id not null,
    path_pattern text not null, -- /blogs/{$1}/posts/{$2}.html -- the numbers correspond to the position of the argument passed to the specified function
    default_args text[] not null default '{}', -- for setting fixed arguments to the function, when only some of the args are specified by the path. array position corresponds to function args position.
    mimetype_id uuid references mimetype(id) -- if this function always returns the same mimetype, set this
);



/******************************************************************************
 * templates
 * - dynamic HTML fragments, parsed and rendered upon request.
 * - could possibly be non-HTML fragments as well.
 * FIXME: UNUSED, refactor w/ resource_function and/or remove???
 ******************************************************************************/

/*
create table endpoint2.template (
    id uuid not null default public.uuid_generate_v4() primary key,
    name text not null default '',
    mimetype_id uuid not null references mimetype(id),
    content text not null default ''
);

create table endpoint2.template_route (
    id uuid not null default public.uuid_generate_v4() primary key,
    template_id uuid not null references endpoint2.template(id) on delete cascade,
    url_pattern text not null default '', -- matching paths may contain arguments from the url to be passed into the template
    args text not null default '{}' -- this route's static arguments to be passed into the template
);
*/




/******************************************************************************
 * endpoint.user
 ******************************************************************************/

/*
create table endpoint2.user (
    id uuid not null default public.uuid_generate_v4() primary key,
    role_id meta2.role_id not null default public.uuid_generate_v4()::text::meta2.role_id,
    email text not null unique,
    name text not null default '',
    active boolean not null default false,
    activation_code uuid not null default public.uuid_generate_v4(),
    created_at timestamp not null default now()
);
*/

/*

regarding triggers on the user table:
this behavior appears to be wrong.  user should be considered a metadata table
on role.  i could see creating a new role when you insert into user (which is
what the insert trigger does) but switching a user from one role to the other
should actually create that role.

-- Trigger on endpoint.user for insert
create or replace function endpoint.user_insert() returns trigger as $$

    declare
        role_exists boolean;

    begin
        -- If a role_id is supplied (thus not generated), make sure this role does not exist
        select exists(select 1 from meta.role where id = NEW.role_id) into role_exists;
        if role_exists then
            raise exception 'Role already exists';
        end if;

        -- Create a new role
        insert into meta.role(name, can_login, inherit) values((NEW.role_id).name, true, true);

        return NEW;
    end;
$$
language plpgsql;


-- Trigger on endpoint.user for update
create or replace function endpoint.user_update() returns trigger as $$

    declare
        role_exists boolean;

    begin
        if OLD.role_id != NEW.role_id then

            -- If a role_id is supplied (thus not generated), make sure this role does not exist
            select exists(select 1 from meta.role where id = NEW.role_id) into role_exists;
            if role_exists then
                raise exception 'Role already exists';
            end if;

            -- Delete old role
            delete from meta.role where id = OLD.role_id;

            -- Create a new role
            insert into meta.role(name) values((NEW.role_id).name);

                    -- This could be accomplished with one query?:
                    -- update meta.role set id = NEW.role_id where id = OLD.role_id;

        end if;

        return NEW;
    end;
$$
language plpgsql;


-- Trigger on endpoint.user for delete
create or replace function endpoint.user_delete() returns trigger as $$
    begin
        -- Delete old role
        delete from meta.role where id = OLD.role_id;
        return OLD;
    end;
$$
language plpgsql;


create trigger endpoint_user_insert_trigger before insert on endpoint.user for each row execute procedure endpoint.user_insert();
create trigger endpoint_user_update_trigger before update on endpoint.user for each row execute procedure endpoint.user_update();
create trigger endpoint_user_delete_trigger before delete on endpoint.user for each row execute procedure endpoint.user_delete();
*/


/******************************************************************************
 * endpoint.current_user
 ******************************************************************************/

/*
-- create view endpoint."current_user" AS SELECT "current_user"() AS "current_user";
create view endpoint2."current_user" as
SELECT id, role_id, email, name from endpoint2."user" where role_id=current_user::text::meta2.role_id;

create function endpoint2."current_user"() returns uuid as $$
SELECT id from endpoint2."user" as "current_user"  where role_id=current_user::text::meta2.role_id;
$$ language sql;
*/

/******************************************************************************
 * endpoint.session
 ******************************************************************************/

/*
create table endpoint2.session (
    id uuid not null default public.uuid_generate_v4() primary key,
    role_id meta2.role_id not null,
    user_id uuid references endpoint2.user(id) on delete cascade
);

create function endpoint2.session(session_id uuid)
    returns setof endpoint2.session as $$
select * from endpoint2.session where id=session_id;
$$
    language sql security definer;

*/