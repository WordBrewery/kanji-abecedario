port module Main exposing (..)

import Html exposing (Html, button, div, text, a)
import Html.Attributes as HA
import Set exposing (Set)
import Array exposing (Array)
import Svg
import Svg.Attributes exposing (viewBox, d, class)
import Html.Events exposing (onClick, onInput)
import Http
import Maybe exposing (withDefault)
import Json.Decode as Decode
import Json.Encode as Encode
import Navigation
import UrlParser as Url exposing ((</>), (<?>), s, int, string, top)


main : Program Never Model Msg
main =
    Navigation.program UrlChange
        { init = init
        , view = view
        , update = update
        , subscriptions = subscriptions
        }



-- MODEL


type alias Dependencies =
    { depString : String, count : Int }


type alias Target =
    { target : String, pos : Int, deps : List Dependencies }


type alias Primitive =
    { paths : List String, target : String, heading : String }


type alias Model =
    { err : String
    , token : String
    , target : Maybe Target
    , primitives : Array Primitive
    , selected : Set String
    , selectedKanjis : Set String
    , userDeps : Maybe String
    , kanjiOnly : List String
    }


init : Navigation.Location -> ( Model, Cmd Msg )
init initialLocation =
    ( Model ""
        "invalid token"
        Nothing
        Array.empty
        Set.empty
        Set.empty
        Nothing
        []
    , Cmd.batch
        [ (case Url.parseHash route initialLocation of
            Just (RoutePos pos) ->
                getPos pos

            Just (RouteTarget target) ->
                getTarget target

            _ ->
                getPos 1
          )
        , getPrimitives
        , getKanjiOnly
        ]
    )


type alias UserDeps =
    -- NOT used in Model! Just for decoding JSON. Model will get `deps` field only.
    { target : String, deps : String }


userDepsDecoder : Decode.Decoder UserDeps
userDepsDecoder =
    Decode.map2 UserDeps
        (Decode.field "target" Decode.string)
        (Decode.field "deps" Decode.string)


depsDecoder : Decode.Decoder Dependencies
depsDecoder =
    Decode.map2 Dependencies
        (Decode.field "sortedDeps" Decode.string)
        (Decode.field "cnt" Decode.int)


targetDecoder : Decode.Decoder Target
targetDecoder =
    Decode.map3 Target
        (Decode.field "target" Decode.string)
        (Decode.field "rowid" Decode.int)
        (Decode.field "deps" (Decode.list depsDecoder))


primitiveDecoder : Decode.Decoder Primitive
primitiveDecoder =
    Decode.map3 Primitive
        (Decode.field "paths" (Decode.list Decode.string))
        (Decode.field "target" Decode.string)
        (Decode.field "heading" Decode.string)



-- URL PARSING


type Route
    = Home
    | RoutePos Int
    | RouteTarget String


route : Url.Parser (Route -> a) a
route =
    Url.oneOf
        [ Url.map Home top
        , Url.map RoutePos (s "pos" </> int)
        , Url.map RouteTarget (s "target" </> string)
        ]


routeToFragment : Route -> String
routeToFragment route =
    case route of
        RoutePos i ->
            "#pos/" ++ (toString i)

        RouteTarget s ->
            "#target/" ++ s

        _ ->
            ""



-- UPDATE


type Msg
    = Login
    | AskFirstNoDeps
    | GotTarget (Result Http.Error Target)
    | GotLocalStorage String
    | GotPrimitives (Result Http.Error (Array Primitive))
    | SelectPrimitive String
    | Record
    | Previous
    | Next
    | Input String
    | Accept String
    | AskForUserDeps
    | GotUserDeps (Result Http.Error UserDeps)
    | UrlChange Navigation.Location
    | AskForTarget
    | GotKanjiOnly (Result Http.Error (List String))


port login : String -> Cmd msg


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        Login ->
            ( model, login "doesntmatter" )

        AskFirstNoDeps ->
            ( model, askFirstNoDeps )

        GotTarget (Ok target) ->
            let
                url =
                    routeToFragment (RoutePos target.pos)
            in
                ( { model | target = Just target }
                , if List.isEmpty target.deps then
                    Navigation.newUrl url
                  else
                    Cmd.batch
                        [ Navigation.newUrl url
                        , askForUserDeps model.token target.target
                        ]
                )

        GotTarget (Err err) ->
            case err of
                -- Could be because of getPos/-1, getTarget/foo, or invalid record
                Http.BadStatus res ->
                    ( { model | err = (toString err) }, Cmd.none )

                _ ->
                    ( { model | err = (toString err) }, Cmd.none )

        AskForUserDeps ->
            ( model
            , model.target
                |> Maybe.map (askForUserDeps model.token << .target)
                |> withDefault Cmd.none
            )

        GotUserDeps (Ok deps) ->
            ( if deps.target == (model.target |> Maybe.map .target |> withDefault "") then
                { model | userDeps = Just deps.deps }
              else
                model
            , Cmd.none
            )

        GotUserDeps (Err err) ->
            case err of
                Http.BadStatus res ->
                    ( { model | err = (toString err), userDeps = Nothing }, Cmd.none )

                -- ( { model | userDeps = Nothing }, Cmd.none )
                _ ->
                    ( { model | err = (toString err) }, Cmd.none )

        GotLocalStorage str ->
            ( { model | token = str }, Cmd.none )

        GotPrimitives (Err err) ->
            ( { model | err = (toString err) }, Cmd.none )

        GotPrimitives (Ok list) ->
            ( { model | primitives = list }, Cmd.none )

        SelectPrimitive str ->
            ( { model
                | selected =
                    if Set.member str model.selected then
                        Set.remove str model.selected
                    else
                        Set.insert str model.selected
              }
            , Cmd.none
            )

        Record ->
            case model.target of
                Nothing ->
                    ( model, Cmd.none )

                Just target ->
                    ( { model | selected = Set.empty }
                    , record
                        model.token
                        target.target
                        (Set.toList <| Set.union model.selected model.selectedKanjis)
                    )

        Previous ->
            ( model
            , model.target
                |> Maybe.map (.pos >> ((+) -1) >> getPos)
                |> withDefault Cmd.none
            )

        Next ->
            ( model
            , model.target
                |> Maybe.map (.pos >> ((+) 1) >> getPos)
                |> withDefault Cmd.none
            )

        Input text ->
            ( { model | selectedKanjis = text |> String.split "" |> Set.fromList }
            , Cmd.none
            )

        Accept str ->
            ( model
            , model.target
                |> Maybe.map
                    (\target -> str |> String.split "," |> record model.token target.target)
                |> withDefault Cmd.none
            )

        UrlChange location ->
            let
                thisroute =
                    Url.parseHash route location
            in
                case thisroute of
                    Just (RoutePos pos) ->
                        ( model
                        , if model.target |> Maybe.map (.pos >> ((/=) pos)) |> withDefault True then
                            getPos pos
                          else
                            Cmd.none
                        )

                    Just (RouteTarget target) ->
                        ( model
                        , if model.target |> Maybe.map (.target >> ((/=) target)) |> withDefault True then
                            getTarget target
                          else
                            Cmd.none
                        )

                    _ ->
                        ( model, Cmd.none )

        AskForTarget ->
            if Set.isEmpty model.selectedKanjis then
                ( model, Cmd.none )
            else
                ( model
                , model.selectedKanjis
                    |> Set.toList
                    |> List.head
                    |> withDefault ""
                    |> getTarget
                )

        GotKanjiOnly (Ok arr) ->
            ( { model | kanjiOnly = arr }, Cmd.none )

        GotKanjiOnly (Err err) ->
            ( { model | err = toString err }, Cmd.none )


askForUserDeps : String -> String -> Cmd Msg
askForUserDeps token target =
    Http.send GotUserDeps
        (Http.request
            { method = "GET"
            , headers = [ Http.header "Authorization" ("Bearer " ++ token) ]
            , url =
                "http://localhost:3000/secured/userDeps/" ++ target
            , body =
                Http.emptyBody
            , expect = Http.expectJson userDepsDecoder
            , timeout = Nothing
            , withCredentials = False
            }
        )


record : String -> String -> List String -> Cmd Msg
record token target deps =
    Http.send GotTarget
        (Http.request
            { method = "POST"
            , headers = [ Http.header "Authorization" ("Bearer " ++ token) ]
            , url =
                "http://localhost:3000/secured/record/" ++ target
            , body =
                Http.jsonBody (Encode.list (List.map Encode.string deps))
            , expect = Http.expectJson targetDecoder
            , timeout = Nothing
            , withCredentials = False
            }
        )


getPrimitives : Cmd Msg
getPrimitives =
    Http.send GotPrimitives
        (Http.get "http://localhost:3000/data/paths.json"
            (Decode.array primitiveDecoder)
        )


getKanjiOnly : Cmd Msg
getKanjiOnly =
    Http.send GotKanjiOnly
        (Http.get "http://localhost:3000/kanjiOnly"
            (Decode.list Decode.string)
        )


askFirstNoDeps : Cmd Msg
askFirstNoDeps =
    Http.send GotTarget (Http.get "http://localhost:3000/firstNoDeps" targetDecoder)


getPos : Int -> Cmd Msg
getPos pos =
    Http.send GotTarget
        (Http.get ("http://localhost:3000/getPos/" ++ (toString pos))
            targetDecoder
        )


getTarget : String -> Cmd Msg
getTarget target =
    Http.send GotTarget (Http.get ("http://localhost:3000/getTarget/" ++ target) targetDecoder)



-- SUBSCRIPTIONS


port gotLocalStorage : (String -> msg) -> Sub msg


subscriptions : Model -> Sub Msg
subscriptions model =
    gotLocalStorage GotLocalStorage



-- VIEW


renderModel : Model -> Html Msg
renderModel model =
    div []
        [ text
            (toString
                { model
                    | primitives = Array.slice 0 1 model.primitives
                    , token = String.slice 0 5 model.token
                    , kanjiOnly = List.take 10 model.kanjiOnly
                }
            )
        ]


view : Model -> Html Msg
view model =
    div []
        [ button [ onClick Login ] [ text "Login from Elm" ]
        , button [] [ text "My kanji" ]
        , button
            [ onClick Previous
            , HA.disabled
                (model.target
                    |> Maybe.map (.pos >> (>=) 1)
                    |> withDefault True
                )
            ]
            [ text "Previous kanji" ]
        , button [ onClick Next ] [ text "Next kanji" ]
        , button [ onClick AskFirstNoDeps ] [ text "First kanji without any votes" ]
        , button [] [ text "First kanji without my votes" ]
        , button [ onClick Record ] [ text "Record" ]
        , Html.input [ HA.placeholder "Enter kanji here", onInput Input ] []
        , button [ onClick AskForTarget ] [ text "Jump to a kanji" ]
        , renderTarget model.target model.userDeps model.primitives
        , renderPrimitives model.selected model.primitives
        , renderPrimitivesDispOnly model.primitives
        , renderKanjis model.kanjiOnly
        , renderModel model
        ]


renderTargetDeps : Target -> Maybe String -> Html Msg
renderTargetDeps target maybeuserdeps =
    Html.ul []
        (List.map
            (\dep ->
                let
                    uservote =
                        maybeuserdeps |> Maybe.map ((==) dep.depString) |> withDefault False
                in
                    Html.li
                        (if uservote then
                            [ class "uservote" ]
                         else
                            []
                        )
                        [ text
                            (dep.depString
                                ++ " ("
                                ++ (toString dep.count)
                                ++ " votes) "
                            )
                        , if uservote then
                            text "(Your selection!)"
                          else
                            button [ onClick (Accept dep.depString) ] [ text "Accept" ]
                        ]
            )
            target.deps
        )


renderTarget : Maybe Target -> Maybe String -> Array Primitive -> Html Msg
renderTarget maybetarget maybeuserdeps primitives =
    case maybetarget of
        Just target ->
            div []
                [ Html.h1 []
                    [ text
                        ("Help us decompose #"
                            ++ (toString target.pos)
                            ++ "! "
                        )
                    , Array.get (target.pos - 1) primitives
                        |> Maybe.map (svgPrimitive "heading-svg")
                        |> withDefault (text target.target)
                    ]
                , renderTargetDeps target maybeuserdeps
                ]

        Nothing ->
            div [] [ text "(Waiting for network)" ]


renderPrimitive : Set String -> Primitive -> Html Msg
renderPrimitive selecteds primitive =
    Svg.svg
        [ viewBox "0 0 109 109"
        , class
            (String.join " "
                [ ("col-" ++ primitive.heading)
                , if Set.member primitive.target selecteds then
                    "primitive-selected"
                  else
                    ""
                ]
            )
        , onClick (SelectPrimitive primitive.target)
        ]
        (List.map (\path -> Svg.path [ d path ] []) primitive.paths)


renderPrimitives : Set String -> Array Primitive -> Html Msg
renderPrimitives selected primitives =
    div [ HA.class "primitive-container" ]
        (List.map (renderPrimitive selected) <| Array.toList primitives)


svgPrimitive : String -> Primitive -> Html Msg
svgPrimitive classname primitive =
    Svg.svg
        [ viewBox "0 0 109 109", class classname ]
        (List.map (\path -> Svg.path [ d path ] []) primitive.paths)


renderPrimitiveDispOnly : Int -> Primitive -> Html Msg
renderPrimitiveDispOnly pos primitive =
    a [ HA.href <| routeToFragment <| RoutePos <| 1 + pos ]
        [ svgPrimitive "" primitive ]


renderPrimitivesDispOnly : Array Primitive -> Html Msg
renderPrimitivesDispOnly primitiveList =
    div [ HA.class "primitive-container-disp" ]
        ((Html.h2 [] [ text "Jump to a primitive to tag it!" ])
            :: (List.indexedMap renderPrimitiveDispOnly <| Array.toList primitiveList)
        )


renderKanji : String -> Html Msg
renderKanji target =
    a [ HA.href <| routeToFragment <| RouteTarget target ]
        [ text target ]


renderKanjis : List String -> Html Msg
renderKanjis stringList =
    div [ HA.class "kanji-container" ]
        ((Html.h2 [] [ text "Jump to a kanji!" ])
            :: (List.map renderKanji stringList)
        )
